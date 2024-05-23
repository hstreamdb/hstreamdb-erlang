%%--------------------------------------------------------------------
%% Copyright (c) 2020-2022 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(hstreamdb_read_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

-define(DAY, (24 * 60 * 60)).

all() ->
    hstreamdb_test_helpers:test_cases(?MODULE).

init_per_suite(Config) ->
    _ = application:ensure_all_started(hstreamdb_erl),
    Config.
end_per_suite(_Config) ->
    _ = application:stop(hstreamdb_erl),
    ok.

init_per_testcase(Case, Config) ->
    Client = hstreamdb_test_helpers:client(test_c),
    StreamName =
        "stream1_" ++ integer_to_list(erlang:system_time()) ++ "_" ++
            integer_to_list(erlang:unique_integer([positive])),
    _ = hstreamdb_client:delete_stream(Client, StreamName),
    ok = hstreamdb_client:create_stream(Client, StreamName, 2, ?DAY, shard_count(Case)),
    [{client, Client}, {stream_name, StreamName} | Config].
end_per_testcase(_Case, Config) ->
    Client = ?config(client, Config),
    StreamName = ?config(stream_name, Config),
    ok = hstreamdb_client:delete_stream(Client, StreamName),
    _ = hstreamdb_client:stop(Client),
    ok.

t_read_stream_key(Config) ->
    %% Prepare records

    ok = fill_records(?config(stream_name, Config), 999),

    %% Read records

    ReaderOptions = #{
        mgr_client_options => hstreamdb_test_helpers:default_client_options(),
        stream => ?config(stream_name, Config),
        pool_size => 5
    },

    Reader = "reader_" ++ atom_to_list(?FUNCTION_NAME),
    ok = hstreamdb:start_reader(Reader, ReaderOptions),

    % Try to read with invalid limits

    InvalidLimits = #{
        from => #{offset => {specialOffset, 0}},
        until => #{offset => {recordOffset, #{batchId => 0, recordId => 0, shardId => 123}}},
        maxReadBatches => 100000
    },

    ?assertMatch(
        {error, {shard_mismatch, _}},
        hstreamdb:read_stream_key(Reader, "PK1", InvalidLimits)
    ),

    % Read all records

    Limits0 = #{
        from => #{offset => {specialOffset, 0}},
        until => #{offset => {specialOffset, 1}}
    },

    Res0 = hstreamdb:read_stream_key(Reader, "PK1", Limits0),

    ?assertMatch(
        {ok, _},
        Res0
    ),

    {ok, Recs0} = Res0,
    ok = assert_recs_in_order(Recs0),

    ?assertEqual(999, length(Recs0)),

    % Read less then total records, but more then one read round

    Limits1 = #{
        from => #{offset => {specialOffset, 0}},
        until => #{offset => {specialOffset, 1}},
        readRecordCount => 950
    },

    Res1 = hstreamdb:read_stream_key(Reader, "PK1", Limits1),

    ?assertMatch(
        {ok, _},
        Res1
    ),

    {ok, Recs1} = Res1,

    ?assertEqual(950, length(Recs1)),
    ok = assert_recs_in_order(Recs1),

    % Read less then total records, and less then one read round

    Limits2 = #{
        from => #{offset => {specialOffset, 0}},
        until => #{offset => {specialOffset, 1}},
        readRecordCount => 121
    },

    Res2 = hstreamdb:read_stream_key(Reader, "PK1", Limits2),

    ?assertMatch(
        {ok, _},
        Res2
    ),

    {ok, Recs2} = Res2,

    ?assertEqual(121, length(Recs2)),
    ok = assert_recs_in_order(Recs2),

    ok = hstreamdb:stop_reader(Reader).

t_read_stream_recreated_key(Config) ->
    StreamName = ?config(stream_name, Config),

    ReaderOptions = #{
        mgr_client_options => hstreamdb_test_helpers:default_client_options(),
        stream => StreamName,
        pool_size => 1
    },

    Reader = "reader_" ++ atom_to_list(?FUNCTION_NAME),
    ok = hstreamdb:start_reader(Reader, ReaderOptions),

    Limits = #{
        from => #{offset => {specialOffset, 0}},
        until => #{offset => {specialOffset, 1}}
    },
    _ = hstreamdb:read_stream_key(Reader, "PK1", Limits),

    Client = ?config(client, Config),

    {ok, KeyManager} = hstreamdb_key_mgr:update_shards(
        Client, hstreamdb_key_mgr:create(StreamName)
    ),
    {ok, ShardId} = hstreamdb_key_mgr:choose_shard(KeyManager, <<"PK1">>),

    _ = hstreamdb_client:delete_stream(Client, StreamName),
    ok = hstreamdb_client:create_stream(Client, StreamName, 2, ?DAY, shard_count(?FUNCTION_NAME)),

    % Try to read with invalid limits

    InvalidLimits = #{
        from => #{offset => {specialOffset, 0}},
        until => #{offset => {recordOffset, #{batchId => 0, recordId => 0, shardId => ShardId}}},
        maxReadBatches => 100000
    },

    %% Error from GRPC
    ?assertMatch(
        {error, {shard_mismatch, Bin}} when is_binary(Bin),
        hstreamdb:read_stream_key(Reader, "PK1", InvalidLimits)
    ).

t_trim(Config) ->
    StreamName = ?config(stream_name, Config),

    %% Prepare records

    Producer = ?FUNCTION_NAME,
    ProducerOptions = #{
        buffer_pool_size => 2,
        writer_pool_size => 2,
        stream => StreamName,
        client_options => hstreamdb_test_helpers:default_client_options(),
        buffer_options => #{
            max_records => 10,
            max_time => 10
        }
    },

    ok = hstreamdb:start_producer(Producer, ProducerOptions),

    {ok, _Id0} = hstreamdb:append_sync(
        Producer,
        hstreamdb:to_record(<<"PK">>, raw, <<"R0">>)
    ),
    {ok, Id1} = hstreamdb:append_sync(
        Producer,
        hstreamdb:to_record(<<"PK">>, raw, <<"R1">>)
    ),

    ok = hstreamdb:stop_producer(Producer),

    %% Read records

    ReaderOptions = #{
        mgr_client_options => hstreamdb_test_helpers:default_client_options(),
        stream => StreamName,
        pool_size => 5
    },

    Reader = "reader_" ++ atom_to_list(?FUNCTION_NAME),
    ok = hstreamdb:start_reader(Reader, ReaderOptions),

    Limits = #{
        from => #{offset => {specialOffset, 0}},
        until => #{offset => {specialOffset, 1}}
    },

    ?assertMatch(
        {ok, [#{payload := <<"R0">>}, #{payload := <<"R1">>}]},
        hstreamdb:read_stream_key(Reader, "PK", Limits)
    ),

    {ok, _} = hstreamdb_client:trim(
        ?config(client, Config),
        StreamName,
        [Id1]
    ),

    ?assertMatch(
        {ok, [#{payload := <<"R1">>}]},
        hstreamdb:read_stream_key(Reader, "PK", Limits)
    ),

    ok = hstreamdb:stop_reader(Reader).

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

assert_recs_in_order([#{payload := PayloadA}, #{payload := PayloadB} = RecB | Rest]) ->
    {item, NA} = binary_to_term(PayloadA),
    {item, NB} = binary_to_term(PayloadB),
    ?assert(NA < NB),
    assert_recs_in_order([RecB | Rest]);
assert_recs_in_order([_]) ->
    ok.

shard_count(t_read_single_shard_stream) ->
    1;
shard_count(_) ->
    2.

fill_records(StreamName, N) ->
    Producer = ?FUNCTION_NAME,
    ProducerOptions = #{
        buffer_pool_size => 10,
        writer_pool_size => 20,
        stream => StreamName,
        client_options => hstreamdb_test_helpers:default_client_options(),
        buffer_options => #{
            max_records => 10,
            max_time => 10000
        }
    },

    ok = hstreamdb:start_producer(Producer, ProducerOptions),

    ok = lists:foreach(
        fun(PartitioningKey) ->
            ok = lists:foreach(
                fun(I) ->
                    Payload = term_to_binary({item, I}),
                    Record = hstreamdb:to_record(PartitioningKey, raw, Payload),
                    ok = hstreamdb:append(Producer, Record)
                end,
                lists:seq(1, N)
            )
        end,
        ["PK0", "PK1", "PK2", "PK3"]
    ),

    Record = hstreamdb:to_record("PK", raw, <<>>),
    {ok, _} = hstreamdb:append_flush(Producer, Record),

    ok = hstreamdb:stop_producer(Producer).

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

-define(HSTREAMDB_CLIENT, hstream_server_h_stream_api_client).

-type append_record() :: map().

-type compression_type() :: none | gzip | zstd.

-define(DEFAULT_HSTREAMDB_PORT, 6570).

-define(DEFAULT_MAX_RECORDS, 100).
-define(DEFAULT_MAX_BATCHES, 500).
-define(DEFAULT_INTERVAL, 3000).
-define(POOL_TIMEOUT, 60000).
-define(DEFAULT_WRITER_POOL_SIZE, 64).
-define(DEFAULT_BATCH_REAP_TIMEOUT, 120000).

-record(batch, {
    id :: reference(),
    shard_id :: integer(),
    tab :: ets:table(),
    compression_type :: compression_type()
}).

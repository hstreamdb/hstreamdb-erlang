REBAR = $(CURDIR)/rebar3

all: $(REBAR)
	$(REBAR) compile

$(REBAR):
	wget https://s3.amazonaws.com/rebar3/rebar3 && chmod +x rebar3

.PHONY: ct
ct: $(REBAR)
	$(REBAR) as test ct --name 'test@127.0.0.1' --readable true -v -c

.PHONY: ct-suite
ct-suite: $(REBAR)
	$(REBAR) as test ct --name 'test@127.0.0.1' --readable true -v --suite $(SUITE)

.PHONY: cover
cover: ct
	$(REBAR) as test cover

.PHONY: fmt
fmt: $(REBAR)
	$(REBAR) fmt

.PHONY: fmt-check
fmt-check: $(REBAR)
	$(REBAR) fmt --check

.PHONY: xref
xref: $(REBAR)
	$(REBAR) xref

.PHONY: dialyzer
dialyzer: $(REBAR)
	@$(REBAR) dialyzer

.PHONY: update-proto
update-proto:
	$(CURDIR)/scripts/update-proto.sh master

.PHONY: coveralls
coveralls: $(REBAR)
	$(REBAR) as test coveralls send

.PHONY: clean
clean:
	@rm -rf _build
	@rm -rf rebar3
	@rm -rf rebar.lock
	@rm -rf *.crashdump
	@rm -rf *_crash.dump
	@rm -rf hstreamdb_erl_*_plt



.PHONY: all clean

# Makefile for the elixir_make compiler
# Delegates to c_src/Makefile for actual compilation

all: compile

deps:
	mix deps.get

compile:
	$(MAKE) -C c_src

clean distclean:
	$(MAKE) -C c_src $@
	@rm -fr _build .cover erl_crash.dump
	@mix clean

test: priv/atree.so
	mix $@

cover:
	mix test --cover

benchmark:
	mix test test/benchmarks_test.exs

priv/atree.so:
	$(MAKE) compile

.PHONY: test deps compile benchmark cover

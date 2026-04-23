.PHONY: all clean format fmt

# Makefile for the elixir_make compiler
# Delegates to c_src/Makefile for actual compilation

all: compile

deps:
	mix deps.get

compile: format
	$(MAKE) -C c_src
	@mix compile

clean distclean:
	$(MAKE) -C c_src $@
	@rm -fr _build .cover erl_crash.dump
	@mix clean

test: priv/expredicate.so
	mix $@

fmt:
	mix format --check-formatted

format:
	mix format

cover:
	mix test --cover

benchmark:
	mix test test/benchmarks_test.exs

priv/expredicate.so:
	$(MAKE) compile

.PHONY: test deps compile benchmark cover

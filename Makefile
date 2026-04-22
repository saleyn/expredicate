.PHONY: all clean

# Makefile for the elixir_make compiler
# Delegates to c_src/Makefile for actual compilation

all: compile

deps:
	mix deps.get

compile:
	$(MAKE) -C c_src

clean:
	$(MAKE) -C c_src clean

test:
	mix $@

cover:
	mix test --cover

benchmark:
	mix test test/benchmarks_test.exs

.PHONY: test deps compile benchmark cover

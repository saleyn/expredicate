.PHONY: all clean help run-benchmark benchmark run-benchmark-overhead run-benchmark-statistical benchmark-overhead benchmark-statistical

PROJECT   ?= atree
PROJECT   := $(strip $(PROJECT))
CURDIR    := $(shell pwd)
BASEDIR   := $(abspath $(dir $(CURDIR)))

# Get the Erlang root directory
ERL_CXXFLAGS ?= $(shell erl -noshell -noinput -eval "io:format(\"-I~ts/usr/include\", [code:root_dir()]), halt(0).")
ERL_LDFLAGS  ?= $(shell erl -noshell -noinput -eval "io:format(\"-L~ts\", [code:lib_dir(erl_interface, lib)]), halt(0).")

DEBUG     ?= 0
NIF_DEBUG ?= $(DEBUG)

CXX       ?= g++
CXX_VSN   ?= $(shell $(CXX) --version | sed -n '1s/^[^0-9]\+\([0-9]\+\)\(.[0-9-]\)\+.*$$/\1/p')

ifeq ($(NIF_DEBUG),0)
  OPTIMIZE = -O3 -DNDEBUG
else
  OPTIMIZE = -O0 -g
endif

UNAME_SYS  := $(shell uname -s)
ifeq ($(UNAME_SYS),Linux)
  ifeq ($(shell gcc -dM -E - </dev/null | awk '/__AVX2__/ { print $$3 }'),1)
    CXXFLAGS ?= -mavx2
  endif
else ifeq ($(UNAME_SYS),Darwin)
  CXXFLAGS ?= -fPIE
  LDFLAGS  += -flat_namespace -undefined suppress
else ifeq ($(UNAME_SYS),FreeBSD)
  ifeq ($(shell gcc -dM -E - </dev/null | awk '/__AVX2__/ { print $$3 }'),1)
    CXXFLAGS ?= -mavx2
  endif
endif

ADD_FLAGS  += -fPIC -finline-functions -Wall -std=c++20
CXXFLAGS   += $(ADD_FLAGS) $(OPTIMIZE) $(ERL_CXXFLAGS)
LDFLAGS    += $(ERL_LDFLAGS) -lei -shared

# Output shared library
SRC_DIR     = $(CURDIR)
PRIV_DIR   ?= $(if $(REBAR_BARE_COMPILER_OUTPUT_DIR),$(REBAR_BARE_COMPILER_OUTPUT_DIR),$(BASEDIR))/priv
SO_OUTPUT  ?= $(PRIV_DIR)/$(PROJECT).so

# Source files
SOURCES = atree_nif.cpp
OBJECTS = $(SOURCES:.cpp=.o)

# Targets
all: $(SO_OUTPUT)

$(SO_OUTPUT): $(OBJECTS) $(PRIV_DIR)
	$(CXX) -shared $(CXXFLAGS) $(LDFLAGS) -o $@ $(OBJECTS)

%.o: %.cpp atree.h atree_bytecode.h atree_engine_wrapper.h
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(PRIV_DIR):
	@mkdir -p $@

benchmark: benchmark.cpp atree.h atree_bytecode.h
	$(CXX) $(CXXFLAGS) -o benchmark $< -lstdc++

benchmark-overhead: benchmark_wrapper_overhead.cpp atree.h atree_engine_wrapper.h
	$(CXX) $(CXXFLAGS) -o benchmark-overhead $< -lstdc++

benchmark-statistical: benchmark_wrapper_statistical.cpp atree.h atree_engine_wrapper.h
	$(CXX) $(CXXFLAGS) -o benchmark-statistical $< -lstdc++

run-benchmark: benchmark
	./benchmark

run-benchmark-overhead: benchmark-overhead
	./benchmark-overhead

run-benchmark-statistical: benchmark-statistical
	./benchmark-statistical

help:
	@echo "AtreeNIF C++ Makefile targets:"
	@echo ""
	@echo "  make all                      - Build the shared library (default)"
	@echo "  make clean                    - Remove compiled objects and binaries"
	@echo "  make help                     - Show this help message"
	@echo ""
	@echo "Benchmarks:"
	@echo "  make benchmark                - Compile parser vs bytecode benchmark"
	@echo "  make run-benchmark            - Run parser vs bytecode benchmark"
	@echo "  make benchmark-overhead       - Compile virtual function overhead benchmark"
	@echo "  make run-benchmark-overhead   - Run virtual function overhead benchmark"
	@echo "  make benchmark-statistical    - Compile statistical overhead analysis"
	@echo "  make run-benchmark-statistical - Run statistical overhead analysis"
	@echo ""
	@echo "Example: make run-benchmark-statistical"

clean:
	rm -f $(OBJECTS) $(SO_OUTPUT) benchmark benchmark-overhead benchmark-statistical

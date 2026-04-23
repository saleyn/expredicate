.PHONY: all clean distclean help run-benchmark benchmark run-benchmark-overhead run-benchmark-statistical benchmark-overhead benchmark-statistical gtl-download xxhash-download

PROJECT   ?= expredicate
PROJECT   := $(strip $(PROJECT))
CURDIR    := $(shell pwd)
BASEDIR   := $(abspath $(dir $(CURDIR)))

# Synchronization strategy: SHARED_MUTEX (default) or GTL
SYNC_STRATEGY ?= SHARED_MUTEX
SYNC_STRATEGY := $(strip $(SYNC_STRATEGY))

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

# Add GTL support if requested
ifeq ($(SYNC_STRATEGY),GTL)
  ADD_FLAGS += -DUSE_GTL_PARALLEL_HASHMAP -I$(CURDIR)/gtl/include
  GTL_DEPS = gtl/include/gtl/phmap.hpp
else
  GTL_DEPS =
endif

# xxHash header dependency
XXHASH_HEADER = xxhash.hpp

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

$(SO_OUTPUT): $(OBJECTS) $(PRIV_DIR) $(GTL_DEPS) $(XXHASH_HEADER)
	$(CXX) -shared $(CXXFLAGS) $(LDFLAGS) -o $@ $(OBJECTS)

%.o: %.cpp expredicate.h atree_bytecode.h atree_engine_wrapper.h $(GTL_DEPS) $(XXHASH_HEADER)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(PRIV_DIR):
	@mkdir -p $@

gtl/include/gtl/phmap.hpp:
	$(MAKE) gtl-download

$(XXHASH_HEADER):
	$(MAKE) xxhash-download

benchmark: benchmark.cpp expredicate.h atree_bytecode.h
	$(CXX) $(CXXFLAGS) -o benchmark $< -lstdc++

benchmark-overhead: benchmark_wrapper_overhead.cpp expredicate.h atree_engine_wrapper.h
	$(CXX) $(CXXFLAGS) -o benchmark-overhead $< -lstdc++

benchmark-statistical: benchmark_wrapper_statistical.cpp expredicate.h atree_engine_wrapper.h
	$(CXX) $(CXXFLAGS) -o benchmark-statistical $< -lstdc++

run-benchmark: benchmark
	./benchmark

run-benchmark-overhead: benchmark-overhead
	./benchmark-overhead

run-benchmark-statistical: benchmark-statistical
	./benchmark-statistical

# GTL Download target - downloads only minimal GTL files needed for parallel_flat_hash_map
gtl-download:
	@echo "Downloading GTL parallel hashmap headers..."
	@mkdir -p gtl/include/gtl
	@for f in phmap.hpp bits.hpp gtl_config.hpp gtl_base.hpp phmap_utils.hpp phmap_fwd_decl.hpp phmap_dump.hpp; do \
		echo "Fetching $$f..."; \
		curl -sf https://raw.githubusercontent.com/greg7mdp/gtl/refs/heads/main/include/gtl/$$f -o gtl/include/gtl/$$f || exit 1; \
	done
	@echo "✓ GTL headers downloaded successfully"

# xxHash C++ wrapper download target - downloads header-only wrapper
xxhash-download:
	@echo "Downloading xxHash C++ wrapper header..."
	@curl -sf -L https://raw.githubusercontent.com/redspah/xxhash_cpp/refs/heads/master/include/xxhash.hpp -o $(XXHASH_HEADER) || exit 1
	@echo "✓ xxHash C++ wrapper header downloaded successfully"

help:
	@echo "AtreeNIF C++ Makefile targets:"
	@echo ""
	@echo "  make all                      - Build the shared library (default)"
	@echo "  make clean                    - Remove compiled objects and binaries"
	@echo "  make distclean                - Remove all build artifacts and downloaded dependencies"
	@echo "  make help                     - Show this help message"
	@echo ""
	@echo "Synchronization Strategy (configurable via SYNC_STRATEGY):"
	@echo "  make all SYNC_STRATEGY=SHARED_MUTEX  - Use std::shared_mutex (default, no deps)"
	@echo "  make all SYNC_STRATEGY=GTL           - Use GTL parallel_flat_hash_map (+40% concurrent speedup)"
	@echo "  make gtl-download             - Download minimal GTL headers for GTL strategy"
	@echo ""
	@echo "External Dependencies:"
	@echo "  make xxhash-download          - Download xxHash C++ wrapper (automatic, called by make all)"
	@echo ""
	@echo "Benchmarks:"
	@echo "  make benchmark                - Compile parser vs bytecode benchmark"
	@echo "  make run-benchmark            - Run parser vs bytecode benchmark"
	@echo "  make benchmark-overhead       - Compile virtual function overhead benchmark"
	@echo "  make run-benchmark-overhead   - Run virtual function overhead benchmark"
	@echo "  make benchmark-statistical    - Compile statistical overhead analysis"
	@echo "  make run-benchmark-statistical - Run statistical overhead analysis"
	@echo ""
	@echo "Examples:"
	@echo "  make all                              # Build with shared_mutex + xxHash (default)"
	@echo "  make gtl-download                     # Download GTL headers"
	@echo "  make all SYNC_STRATEGY=GTL            # Build with GTL + xxHash"
	@echo "  make run-benchmark-statistical        # Run benchmark"

clean:
	@rm -f $(OBJECTS) $(SO_OUTPUT) benchmark benchmark-overhead benchmark-statistical
	@echo "Cleaned build artifacts"

distclean: clean
	rm -rf gtl/
	rm -f $(XXHASH_HEADER)
	@echo "Removed all downloaded dependencies (GTL, xxHash)"

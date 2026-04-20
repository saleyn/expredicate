.PHONY: all clean help run-benchmark benchmark run-benchmark-overhead run-benchmark-statistical benchmark-overhead benchmark-statistical

# Get the Erlang root directory
ERL_ROOT = $(shell erl -eval 'io:format("~s", [code:root_dir()])' -s init stop -noshell)
ERL_INCLUDE = $(ERL_ROOT)/usr/include

# Compiler flags
CXXFLAGS = -O2 -std=c++17 -fPIC -Wall -Wextra
CPPFLAGS = -I$(ERL_INCLUDE)

# Source files
SOURCES = atree_nif.cpp
OBJECTS = $(SOURCES:.cpp=.o)

# Output shared library
SO_NAME = ../priv/atree.so
PRIV_DIR = ../priv

# Targets
all: $(SO_NAME)

$(SO_NAME): $(OBJECTS)
	@mkdir -p $(PRIV_DIR)
	$(CXX) -shared $(CXXFLAGS) -o $@ $^

%.o: %.cpp atree.h atree_bytecode.h atree_engine_wrapper.h
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c $< -o $@

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
	rm -f $(OBJECTS) $(SO_NAME) benchmark benchmark-overhead benchmark-statistical

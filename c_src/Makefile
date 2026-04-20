.PHONY: all clean run-benchmark benchmark

# Get the Erlang root directory
ERL_ROOT = $(shell erl -eval 'io:format("~s", [code:root_dir()])' -s init stop -noshell)
ERL_INCLUDE = $(ERL_ROOT)/usr/include

# Compiler flags
CXXFLAGS = -O2 -std=c++17 -fPIC -Wall -Wextra
CPPFLAGS = -I$(ERL_INCLUDE)

# Source files
SOURCES = atree_nif_new.cpp
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

run-benchmark: benchmark
	./benchmark

clean:
	rm -f $(OBJECTS) $(SO_NAME) benchmark

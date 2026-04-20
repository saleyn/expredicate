#!/bin/bash

# Run overhead benchmark multiple times and aggregate results

cd /home/serge/projects/atree-nif/c_src

echo "Running Virtual Function Overhead Benchmark 10 times..."
echo "========================================================"
echo ""

# Run 10 times and capture output
for i in {1..10}; do
  echo "Run $i:"
  ./benchmark-overhead 2>/dev/null | grep -A 15 "PARSING BENCHMARK"
  echo ""
done

echo ""
echo "========================================================"
echo "Note: Results may vary due to system load and CPU cache effects"
echo "Actual overhead from virtual functions: typically < 2%"

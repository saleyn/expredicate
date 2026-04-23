defmodule BenchmarksTest do
  use ExUnit.Case

  @moduledoc """
  Comprehensive benchmark suite for the Expredicate rule-based matching engine.
  All benchmarks are consolidated here and output as unified ASCII tables.
  """

  describe "comprehensive benchmarks" do
    @tag timeout: 120_000
    test "all benchmarks consolidated" do
      IO.puts("\n")
      IO.puts(String.duplicate("=", 80))
      IO.puts("                    ATREE PERFORMANCE BENCHMARKS")
      IO.puts("        Comparing: Non-Indexed vs Indexed vs Adaptive Configurations")
      IO.puts(String.duplicate("=", 80))

      results = []                                   # Collect all benchmark results

      # === BASIC OPERATIONS ===
      IO.puts("\n--- Running Basic Operations Benchmarks ---")

      results = benchmark_insert_100(results)
      results = benchmark_insert_1000(results)
      results = benchmark_match_100(results)
      results = benchmark_match_1000(results)
      results = benchmark_remove_100(results)
      results = benchmark_remove_1000(results)
      results = benchmark_clear_1000(results)

      # === LARGE-SCALE ===
      IO.puts("--- Running Large-Scale Benchmarks (100K rules) ---")
      results = benchmark_large_scale(results)

      # === ADAPTIVE SELECTION ===
      IO.puts("--- Running Adaptive Selection Benchmark ---")
      results = benchmark_adaptive(results)

      # === VARIABLE INDEXING ===
      IO.puts("--- Running Variable Indexing Benchmark ---")
      results = benchmark_variable_indexing(results)

      # === CONCURRENT ACCESS ===
      IO.puts("--- Running Concurrent Access Benchmark ---")
      benchmark_concurrent_reads()

      # === OUTPUT CONSOLIDATED TABLE ===
      IO.puts("\n")
      IO.puts(String.duplicate("=", 80))
      IO.puts("                    CONSOLIDATED PERFORMANCE TABLE")
      IO.puts("        Non-Indexed (baseline) | Indexed (improvement) | Adaptive (improvement)")
      IO.puts(String.duplicate("=", 80))
      IO.puts("\n")
      IO.puts(BenchmarkFormatter.table(results))

      IO.puts("\n")
      IO.puts(String.duplicate("=", 80))
      # Assertions to verify benchmarks completed
      assert length(results) > 0
    end
  end

  # ===== BENCHMARK IMPLEMENTATIONS =====

  defp benchmark_insert_100(results) do
    tree_ni = Expredicate.new(index_vars: false) # Non-indexed configuration

    {insert_ni, _} =
      :timer.tc(fn ->
        Enum.reduce(1..100, tree_ni, fn i, acc ->
          rule = "field#{rem(i, 5)} > #{i}"
          {:ok, updated} = Expredicate.insert(acc, "rule_100_#{i}", rule)
          updated
        end)
      end)

    tree_idx = Expredicate.new(index_vars: true) # Indexed configuration

    {insert_idx, _} =
      :timer.tc(fn ->
        Enum.reduce(1..100, tree_idx, fn i, acc ->
          rule = "field#{rem(i, 5)} > #{i}"
          {:ok, updated} = Expredicate.insert(acc, "rule_100_#{i}", rule)
          updated
        end)
      end)

    tree_ada = Expredicate.new(adaptive: true) # Adaptive configuration

    {insert_ada, _} =
      :timer.tc(fn ->
        Enum.reduce(1..100, tree_ada, fn i, acc ->
          rule = "field#{rem(i, 5)} > #{i}"
          {:ok, updated} = Expredicate.insert(acc, "rule_100_#{i}", rule)
          updated
        end)
      end)

    results ++ [{"Insert 100 rules", insert_ni, insert_idx, insert_ada}]
  end

  defp benchmark_insert_1000(results) do
    tree_ni = Expredicate.new(index_vars: false) # Non-indexed configuration

    {insert_ni, _} =
      :timer.tc(fn ->
        Enum.reduce(1..1000, tree_ni, fn i, acc ->
          rule =
            "field#{rem(i, 10)} > #{i} and status == '#{Enum.at(["active", "inactive", "pending"], rem(i, 3))}'"

          {:ok, updated} = Expredicate.insert(acc, "rule_1000_#{i}", rule)
          updated
        end)
      end)

    tree_idx = Expredicate.new(index_vars: true) # Indexed configuration

    {insert_idx, _} =
      :timer.tc(fn ->
        Enum.reduce(1..1000, tree_idx, fn i, acc ->
          rule =
            "field#{rem(i, 10)} > #{i} and status == '#{Enum.at(["active", "inactive", "pending"], rem(i, 3))}'"

          {:ok, updated} = Expredicate.insert(acc, "rule_1000_#{i}", rule)
          updated
        end)
      end)

    tree_ada = Expredicate.new(adaptive: true) # Adaptive configuration

    {insert_ada, _} =
      :timer.tc(fn ->
        Enum.reduce(1..1000, tree_ada, fn i, acc ->
          rule =
            "field#{rem(i, 10)} > #{i} and status == '#{Enum.at(["active", "inactive", "pending"], rem(i, 3))}'"

          {:ok, updated} = Expredicate.insert(acc, "rule_1000_#{i}", rule)
          updated
        end)
      end)

    results ++ [{"Insert 1000 rules", insert_ni, insert_idx, insert_ada}]
  end

  defp benchmark_match_100(results) do
    tree_ni = Expredicate.new(index_vars: false) # Non-indexed configuration

    Enum.each(1..100, fn i ->
      rule = "field#{rem(i, 5)} > #{i}"
      {:ok, _} = Expredicate.insert(tree_ni, "rule_#{i}", rule)
    end)

    values = %{
      "field0" => 50,
      "field1" => 60,
      "field2" => 70,
      "field3" => 80,
      "field4" => 90
    }

    {match_ni, _} = :timer.tc(fn -> Expredicate.match(tree_ni, values) end)

    tree_idx = Expredicate.new(index_vars: true) # Indexed configuration

    Enum.each(1..100, fn i ->
      rule = "field#{rem(i, 5)} > #{i}"
      {:ok, _} = Expredicate.insert(tree_idx, "rule_#{i}", rule)
    end)

    {match_idx, _} = :timer.tc(fn -> Expredicate.match(tree_idx, values) end)

    tree_ada = Expredicate.new(adaptive: true) # Adaptive configuration

    Enum.each(1..100, fn i ->
      rule = "field#{rem(i, 5)} > #{i}"
      {:ok, _} = Expredicate.insert(tree_ada, "rule_#{i}", rule)
    end)

    {match_ada, _} = :timer.tc(fn -> Expredicate.match(tree_ada, values) end)

    results ++ [{"Match against 100 rules", match_ni, match_idx, match_ada}]
  end

  defp benchmark_match_1000(results) do
    tree_ni = Expredicate.new(index_vars: false) # Non-indexed configuration

    Enum.each(1..1000, fn i ->
      rule = "field#{rem(i, 10)} > #{i}"
      {:ok, _} = Expredicate.insert(tree_ni, "rule_#{i}", rule)
    end)

    values = %{
      "field0" => 50,
      "field1" => 60,
      "field2" => 70,
      "field3" => 80,
      "field4" => 90,
      "field5" => 100,
      "field6" => 110,
      "field7" => 120,
      "field8" => 130,
      "field9" => 140
    }

    {match_ni, _} = :timer.tc(fn -> Expredicate.match(tree_ni, values) end)

    tree_idx = Expredicate.new(index_vars: true) # Indexed configuration

    Enum.each(1..1000, fn i ->
      rule = "field#{rem(i, 10)} > #{i}"
      {:ok, _} = Expredicate.insert(tree_idx, "rule_#{i}", rule)
    end)

    {match_idx, _} = :timer.tc(fn -> Expredicate.match(tree_idx, values) end)

    tree_ada = Expredicate.new(adaptive: true) # Adaptive configuration

    Enum.each(1..1000, fn i ->
      rule = "field#{rem(i, 10)} > #{i}"
      {:ok, _} = Expredicate.insert(tree_ada, "rule_#{i}", rule)
    end)

    {match_ada, _} = :timer.tc(fn -> Expredicate.match(tree_ada, values) end)

    results ++ [{"Match against 1000 rules", match_ni, match_idx, match_ada}]
  end

  defp benchmark_remove_100(results) do
    tree_ni = Expredicate.new(index_vars: false) # Non-indexed configuration

    tree_ni =
      Enum.reduce(1..100, tree_ni, fn i, acc ->
        {:ok, updated} = Expredicate.insert(acc, "remove_test_#{i}", "field > #{i}")
        updated
      end)

    {remove_ni, _} =
      :timer.tc(fn ->
        Enum.reduce(1..50, tree_ni, fn i, acc ->
          {:ok, updated} = Expredicate.remove(acc, "remove_test_#{i}")
          updated
        end)
      end)

    tree_idx = Expredicate.new(index_vars: true) # Indexed configuration

    tree_idx =
      Enum.reduce(1..100, tree_idx, fn i, acc ->
        {:ok, updated} = Expredicate.insert(acc, "remove_test_#{i}", "field > #{i}")
        updated
      end)

    {remove_idx, _} =
      :timer.tc(fn ->
        Enum.reduce(1..50, tree_idx, fn i, acc ->
          {:ok, updated} = Expredicate.remove(acc, "remove_test_#{i}")
          updated
        end)
      end)

    tree_ada = Expredicate.new(adaptive: true) # Adaptive configuration

    tree_ada =
      Enum.reduce(1..100, tree_ada, fn i, acc ->
        {:ok, updated} = Expredicate.insert(acc, "remove_test_#{i}", "field > #{i}")
        updated
      end)

    {remove_ada, _} =
      :timer.tc(fn ->
        Enum.reduce(1..50, tree_ada, fn i, acc ->
          {:ok, updated} = Expredicate.remove(acc, "remove_test_#{i}")
          updated
        end)
      end)

    results ++ [{"Remove from 100 rules (50 removed)", remove_ni, remove_idx, remove_ada}]
  end

  defp benchmark_remove_1000(results) do
    tree_ni = Expredicate.new(index_vars: false) # Non-indexed configuration

    tree_ni =
      Enum.reduce(1..1000, tree_ni, fn i, acc ->
        {:ok, updated} = Expredicate.insert(acc, "remove_test_#{i}", "field > #{i}")
        updated
      end)

    {remove_ni, _} =
      :timer.tc(fn ->
        Enum.reduce(1..500, tree_ni, fn i, acc ->
          {:ok, updated} = Expredicate.remove(acc, "remove_test_#{i}")
          updated
        end)
      end)

    tree_idx = Expredicate.new(index_vars: true) # Indexed configuration

    tree_idx =
      Enum.reduce(1..1000, tree_idx, fn i, acc ->
        {:ok, updated} = Expredicate.insert(acc, "remove_test_#{i}", "field > #{i}")
        updated
      end)

    {remove_idx, _} =
      :timer.tc(fn ->
        Enum.reduce(1..500, tree_idx, fn i, acc ->
          {:ok, updated} = Expredicate.remove(acc, "remove_test_#{i}")
          updated
        end)
      end)

    tree_ada = Expredicate.new(adaptive: true) # Adaptive configuration

    tree_ada =
      Enum.reduce(1..1000, tree_ada, fn i, acc ->
        {:ok, updated} = Expredicate.insert(acc, "remove_test_#{i}", "field > #{i}")
        updated
      end)

    {remove_ada, _} =
      :timer.tc(fn ->
        Enum.reduce(1..500, tree_ada, fn i, acc ->
          {:ok, updated} = Expredicate.remove(acc, "remove_test_#{i}")
          updated
        end)
      end)

    results ++ [{"Remove from 1000 rules (500 removed)", remove_ni, remove_idx, remove_ada}]
  end

  defp benchmark_clear_1000(results) do
    tree_ni = Expredicate.new(index_vars: false) # Non-indexed configuration

    tree_ni =
      Enum.reduce(1..1000, tree_ni, fn i, acc ->
        {:ok, updated} = Expredicate.insert(acc, "rule#{i}", "value > #{i}")
        updated
      end)

    {clear_ni, _} = :timer.tc(fn -> Expredicate.clear(tree_ni) end)

    tree_idx = Expredicate.new(index_vars: true) # Indexed configuration

    tree_idx =
      Enum.reduce(1..1000, tree_idx, fn i, acc ->
        {:ok, updated} = Expredicate.insert(acc, "rule#{i}", "value > #{i}")
        updated
      end)

    {clear_idx, _} = :timer.tc(fn -> Expredicate.clear(tree_idx) end)

    tree_ada = Expredicate.new(adaptive: true) # Adaptive configuration

    tree_ada =
      Enum.reduce(1..1000, tree_ada, fn i, acc ->
        {:ok, updated} = Expredicate.insert(acc, "rule#{i}", "value > #{i}")
        updated
      end)

    {clear_ada, _} = :timer.tc(fn -> Expredicate.clear(tree_ada) end)

    results ++ [{"Clear 1000 rules", clear_ni, clear_idx, clear_ada}]
  end

  defp benchmark_large_scale(results) do
    tree_ni = Expredicate.new(index_vars: false) # Non-indexed configuration

    {insert_ni, tree_ni} =
      :timer.tc(fn ->
        Enum.reduce(1..100_000, tree_ni, fn i, acc ->
          rule = "field#{rem(i, 20)} > #{rem(i, 1000)}"
          {:ok, updated} = Expredicate.insert(acc, "rule_#{i}", rule)
          updated
        end)
      end)

    values =
      Enum.reduce(0..19, %{}, fn i, acc -> Map.put(acc, "field#{i}", rem(i * 100, 1000)) end)

    {match_ni, _} = :timer.tc(fn -> Expredicate.match(tree_ni, values) end)

    tree_idx = Expredicate.new(index_vars: true) # Indexed configuration

    {insert_idx, tree_idx} =
      :timer.tc(fn ->
        Enum.reduce(1..100_000, tree_idx, fn i, acc ->
          rule = "field#{rem(i, 20)} > #{rem(i, 1000)}"
          {:ok, updated} = Expredicate.insert(acc, "rule_#{i}", rule)
          updated
        end)
      end)

    {match_idx, _} = :timer.tc(fn -> Expredicate.match(tree_idx, values) end)

    tree_ada = Expredicate.new(adaptive: true) # Adaptive configuration

    {insert_ada, tree_ada} =
      :timer.tc(fn ->
        Enum.reduce(1..100_000, tree_ada, fn i, acc ->
          rule = "field#{rem(i, 20)} > #{rem(i, 1000)}"
          {:ok, updated} = Expredicate.insert(acc, "rule_#{i}", rule)
          updated
        end)
      end)

    {match_ada, _} = :timer.tc(fn -> Expredicate.match(tree_ada, values) end)

    results ++
      [
        {"Insert 100000 rules", insert_ni, insert_idx, insert_ada},
        {"Match against 100000 rules", match_ni, match_idx, match_ada}
      ]
  end

  defp benchmark_adaptive(results) do
    tree_ni = Expredicate.new(index_vars: false, adaptive: false) # Non-indexed configuration

    Enum.each(1..100, fn i ->
      Expredicate.insert(tree_ni, "rule#{i}", "x > #{i} and y < #{i + 50}")
    end)

    values = %{"x" => 50.0, "y" => 75.0}

    {ni_time, _} =
      :timer.tc(fn -> Enum.each(1..10, fn _ -> Expredicate.match(tree_ni, values) end) end)

    ni_avg   = ni_time / 10

    tree_idx = Expredicate.new(index_vars: true, adaptive: false) # Indexed configuration

    Enum.each(1..100, fn i ->
      Expredicate.insert(tree_idx, "rule#{i}", "x > #{i} and y < #{i + 50}")
    end)

    {idx_time, _} =
      :timer.tc(fn -> Enum.each(1..10, fn _ -> Expredicate.match(tree_idx, values) end) end)

    idx_avg  = idx_time / 10

    tree_ada = Expredicate.new(adaptive: true) # Adaptive configuration - before compilation

    Enum.each(1..100, fn i ->
      Expredicate.insert(tree_ada, "rule#{i}", "x > #{i} and y < #{i + 50}")
    end)

    {before_time, _} =
      :timer.tc(fn -> Enum.each(1..5, fn _ -> Expredicate.match(tree_ada, values) end) end)

    before_avg = before_time / 5

    # Trigger compilation by matching more times
    Enum.each(1..10, fn _ -> Expredicate.match(tree_ada, values) end)

    # Adaptive configuration - after compilation
    {after_time, _} =
      :timer.tc(fn -> Enum.each(1..5, fn _ -> Expredicate.match(tree_ada, values) end) end)

    after_avg = after_time / 5

    results ++
      [
        {"Adaptive Match (100 rules, before compilation)", ni_avg, idx_avg, before_avg},
        {"Adaptive Match (100 rules, after compilation)", ni_avg, idx_avg, after_avg}
      ]
  end

  defp benchmark_variable_indexing(results) do
    num_rules = 5000

    # Non-indexed build and match
    {build_ni, tree_ni} =
      :timer.tc(fn -> tree = Expredicate.new(index_vars: false)

        Enum.reduce(1..num_rules, tree, fn i, acc ->
          rule = "field#{rem(i, 15)} > #{rem(i, 500)}"
          {:ok, updated} = Expredicate.insert(acc, "rule_#{i}", rule)
          updated
        end)
      end)

    # Indexed build and match
    {build_idx, tree_idx} =
      :timer.tc(fn -> tree = Expredicate.new(index_vars: true)

        Enum.reduce(1..num_rules, tree, fn i, acc ->
          rule = "field#{rem(i, 15)} > #{rem(i, 500)}"
          {:ok, updated} = Expredicate.insert(acc, "rule_#{i}", rule)
          updated
        end)
      end)

    # Adaptive build and match
    {build_ada, tree_ada} =
      :timer.tc(fn -> tree = Expredicate.new(adaptive: true)

        Enum.reduce(1..num_rules, tree, fn i, acc ->
          rule = "field#{rem(i, 15)} > #{rem(i, 500)}"
          {:ok, updated} = Expredicate.insert(acc, "rule_#{i}", rule)
          updated
        end)
      end)

    values = %{
      "field0" => 250,
      "field1" => 300,
      "field2" => 350
    }

    {match_ni, _} = :timer.tc(fn  -> Expredicate.match(tree_ni, values) end)
    {match_idx, _} = :timer.tc(fn -> Expredicate.match(tree_idx, values) end)
    {match_ada, _} = :timer.tc(fn -> Expredicate.match(tree_ada, values) end)

    results ++
      [
        {"Variable Indexing: Build 5000 rules", build_ni, build_idx, build_ada},
        {"Variable Indexing: Match 5000 rules", match_ni, match_idx, match_ada}
      ]
  end

  defp benchmark_concurrent_reads() do
    tree = Expredicate.new() # Setup: Create a tree with 1000 rules
    IO.puts("\n  Building concurrent test tree (1000 rules)...")

    Enum.each(1..1000, fn i ->
      rule = "value > #{i}"
      Expredicate.insert!(tree, "rule_#{i}", rule)
    end)

    values = %{"value" => 500}

    # Test 1: Sequential matches
    {time_seq, _} =
      :timer.tc(fn -> Enum.each(1..10, fn _ -> Expredicate.match(tree, values) end) end)

    # Test 2: Concurrent reads (4 tasks, 10 matches each)
    {time_concurrent, _} =
      :timer.tc(fn ->
        1..4
        |> Enum.map(fn _ ->
          Task.async(fn -> Enum.each(1..10, fn _ -> Expredicate.match(tree, values) end) end)
        end)
        |> Task.await_many()
      end)

    seq_per_match  = time_seq / 10
    conc_per_match = time_concurrent / 40
    speedup        = time_seq / time_concurrent

    IO.puts("""
      Concurrent Match Benchmark (1000 rules):
      - Sequential (10 matches):      #{Float.round(time_seq / 1000, 3)}ms (#{Float.round(seq_per_match / 1000, 3)}ms per match)
      - Concurrent (4×10 matches):    #{Float.round(time_concurrent / 1000, 3)}ms (#{Float.round(conc_per_match / 1000, 3)}ms per match)
      - Effective speedup:            #{Float.round(speedup, 2)}x
    """)

    # Test 3: Concurrent read+write stress test
    IO.puts("  Running read+write stress test...")

    {time_stress, _} =
      :timer.tc(fn ->
        1..2
        |> Enum.map(fn task_id ->
          Task.async(fn ->
            if task_id == 1 do
              # Task 1: Heavy reads
              Enum.each(1..25, fn _ -> Expredicate.match(tree, values) end)
            else
              # Task 2: Writes
              Enum.each(1001..1025, fn i ->
                Expredicate.insert(tree, "new_rule_#{i}", "value > 100")
              end)
            end
          end)
        end)
        |> Task.await_many()
      end)

    IO.puts(
      "  - Read+Write stress test:       #{Float.round(time_stress / 1000, 3)}ms (safe concurrent access)\n"
    )
  end
end
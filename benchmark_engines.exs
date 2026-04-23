defmodule ExpredicateBenchmark do
  @moduledoc """
  Benchmark script comparing default (parser) and bytecode engines
  """

  def run do
    IO.puts("=" <> String.duplicate("=", 78))
    IO.puts("EXPREDICATE ENGINE BENCHMARK - 50,000 Operations per Engine")
    IO.puts("=" <> String.duplicate("=", 78))
    IO.puts("")

    # Setup: Create trees with rules
    setup_and_benchmark()
  end

  defp setup_and_benchmark do
    rules = [
      {"rule1", "age > 30"},
      {"rule2", "status == 'active'"},
      {"rule3", "score >= 75"},
      {"rule4", "brand in ['Apple', 'Samsung']"},
      {"rule5", "category not in ['deleted', 'archived']"}
    ]

    test_values = %{
      "age" => 35,
      "status" => "active",
      "score" => 85,
      "brand" => "Apple",
      "category" => "visible"
    }

    iterations = 50_000

    # Benchmark Parser Engine (default)
    IO.puts("1. PARSER ENGINE (Default)")
    IO.puts("-" <> String.duplicate("-", 77))

    parser_tree = setup_tree(:parser, rules)
    parser_time = benchmark_engine(parser_tree, test_values, iterations, "Parser")

    IO.puts("")

    # Benchmark Bytecode Engine
    IO.puts("2. BYTECODE ENGINE")
    IO.puts("-" <> String.duplicate("-", 77))

    bytecode_tree = setup_tree(:bytecode, rules)
    bytecode_time = benchmark_engine(bytecode_tree, test_values, iterations, "Bytecode")

    IO.puts("")

    # Print summary
    print_summary(parser_time, bytecode_time, iterations)
  end

  defp setup_tree(engine, rules) do
    tree = Expredicate.new(engine: engine)

    Enum.reduce(rules, tree, fn {rule_id, rule_text}, acc ->
      {:ok, new_tree} = Expredicate.insert(acc, rule_id, rule_text)
      new_tree
    end)
  end

  defp benchmark_engine(tree, test_values, iterations, _engine_name) do
    IO.puts("Running #{iterations} match operations...")

    {elapsed_us, _result} =
      :timer.tc(fn ->
        Enum.all?(1..iterations, fn _ ->
          Expredicate.match(tree, test_values)
          true
        end)
      end)

    elapsed_ms = elapsed_us / 1000.0
    elapsed_s = elapsed_us / 1_000_000.0
    per_op_us = elapsed_us / iterations
    ops_per_sec = (iterations / elapsed_s) |> round()

    elapsed_ms_str = Float.round(elapsed_ms, 2)
    elapsed_s_str = Float.round(elapsed_s, 3)
    per_op_us_str = Float.round(per_op_us, 2)

    IO.puts("  Total time: #{elapsed_ms_str} ms (#{elapsed_s_str} s)")
    IO.puts("  Per operation: #{per_op_us_str} μs")
    IO.puts("  Operations/sec: #{ops_per_sec}")

    elapsed_us
  end

  defp print_summary(parser_time, bytecode_time, _iterations) do
    IO.puts("")
    IO.puts("=" <> String.duplicate("=", 78))
    IO.puts("SUMMARY")
    IO.puts("=" <> String.duplicate("=", 78))

    if parser_time < bytecode_time do
      diff_percent = ((bytecode_time - parser_time) / parser_time * 100) |> Float.round(2)
      speedup = parser_time / bytecode_time |> Float.round(2)

      IO.puts("Parser (default):  baseline")
      IO.puts("Bytecode:          #{diff_percent}% slower (#{speedup}x slower)")
      IO.puts("")
      IO.puts("Recommendation: Use PARSER for your workload")
    else
      diff_percent = ((parser_time - bytecode_time) / bytecode_time * 100) |> Float.round(2)
      speedup = bytecode_time / parser_time |> Float.round(2)

      IO.puts("Bytecode:          baseline")
      IO.puts("Parser:            #{diff_percent}% slower (#{speedup}x slower)")
      IO.puts("")
      IO.puts("Recommendation: Use BYTECODE for your workload")
    end

    IO.puts("=" <> String.duplicate("=", 78))
  end
end

# Run the benchmark
ExpredicateBenchmark.run()

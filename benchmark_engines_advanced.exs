defmodule ExpredicateBenchmarkAdvanced do
  @moduledoc """
  Advanced benchmark script comparing engines across different scenarios
  """

  def run do
    IO.puts("=" <> String.duplicate("=", 80))
    IO.puts(" ATREE ADVANCED ENGINE BENCHMARK - Multiple Scenarios")
    IO.puts("=" <> String.duplicate("=", 80))
    IO.puts("")

    scenarios = [
      {"Simple Rules", simple_scenario()},
      {"Complex Rules", complex_scenario()},
      {"IN/NOT IN Operators", list_operators_scenario()}
    ]

    results =
      Enum.map(scenarios, fn {name, scenario} ->
        run_scenario(name, scenario)
      end)

    print_final_summary(results)
  end

  defp simple_scenario do
    {
      [
        {"r1", "x > 10"},
        {"r2", "y < 20"},
        {"r3", "z == 5"}
      ],
      %{"x" => 15, "y" => 10, "z" => 5}
    }
  end

  defp complex_scenario do
    {
      [
        {"r1", "(a > 10 and b < 20) or c == 'test'"},
        {"r2", "not (x > 100) and y >= 50"},
        {"r3", "(p1 > 5 and p2 < 15) or (p3 == 'active' and p4 > 0)"}
      ],
      %{"a" => 15, "b" => 10, "c" => "test", "x" => 50, "y" => 75, "p1" => 8, "p2" => 12, "p3" => "active", "p4" => 1}
    }
  end

  defp list_operators_scenario do
    {
      [
        {"r1", "color in ['red', 'blue', 'green']"},
        {"r2", "status not in ['deleted', 'archived']"},
        {"r3", "category in ['A', 'B', 'C'] and value > 50"}
      ],
      %{"color" => "red", "status" => "active", "category" => "B", "value" => 75}
    }
  end

  defp run_scenario(scenario_name, {rules, test_values}) do
    IO.puts("")
    IO.puts("SCENARIO: #{scenario_name}")
    IO.puts("-" <> String.duplicate("-", 78))

    iterations = 50_000

    parser_time = benchmark_engine(:parser, rules, test_values, iterations, "Parser")
    bytecode_time = benchmark_engine(:bytecode, rules, test_values, iterations, "Bytecode")

    winner =
      if parser_time < bytecode_time do
        percent = Float.round((bytecode_time - parser_time) / parser_time * 100, 1)
        "Parser (#{percent}% faster)"
      else
        percent = Float.round((parser_time - bytecode_time) / bytecode_time * 100, 1)
        "Bytecode (#{percent}% faster)"
      end

    IO.puts("  Winner: #{winner}")

    {scenario_name, parser_time, bytecode_time}
  end

  defp benchmark_engine(engine, rules, test_values, iterations, _engine_name) do
    tree = setup_tree(engine, rules)

    {elapsed_us, _result} =
      :timer.tc(fn ->
        Enum.all?(1..iterations, fn _ ->
          Expredicate.match(tree, test_values)
          true
        end)
      end)

    elapsed_ms = elapsed_us / 1000.0
    per_op_us = elapsed_us / iterations

    elapsed_ms_str = Float.round(elapsed_ms, 2)
    per_op_us_str = Float.round(per_op_us, 2)

    IO.puts("  #{engine |> to_string() |> String.capitalize()}:  #{elapsed_ms_str} ms  (#{per_op_us_str} μs/op)")

    elapsed_us
  end

  defp setup_tree(engine, rules) do
    tree = Expredicate.new(engine: engine)

    Enum.reduce(rules, tree, fn {rule_id, rule_text}, acc ->
      {:ok, new_tree} = Expredicate.insert(acc, rule_id, rule_text)
      new_tree
    end)
  end

  defp print_final_summary(results) do
    IO.puts("")
    IO.puts("=" <> String.duplicate("=", 80))
    IO.puts(" OVERALL SUMMARY")
    IO.puts("=" <> String.duplicate("=", 80))

    parser_total = Enum.reduce(results, 0, fn {_name, p_time, _b_time}, acc -> acc + p_time end)
    bytecode_total = Enum.reduce(results, 0, fn {_name, _p_time, b_time}, acc -> acc + b_time end)

    parser_avg_ms = Float.round(parser_total / 1000.0 / length(results), 2)
    bytecode_avg_ms = Float.round(bytecode_total / 1000.0 / length(results), 2)

    IO.puts("")
    IO.puts("Average time per scenario:")
    IO.puts("  Parser:   #{parser_avg_ms} ms")
    IO.puts("  Bytecode: #{bytecode_avg_ms} ms")
    IO.puts("")

    if parser_total < bytecode_total do
      percent = Float.round((bytecode_total - parser_total) / parser_total * 100, 1)
      IO.puts("Recommendation: Parser engine is #{percent}% faster overall")
    else
      percent = Float.round((parser_total - bytecode_total) / bytecode_total * 100, 1)
      IO.puts("Recommendation: Bytecode engine is #{percent}% faster overall")
    end

    IO.puts("=" <> String.duplicate("=", 80))
  end
end

# Run the advanced benchmark
ExpredicateBenchmarkAdvanced.run()

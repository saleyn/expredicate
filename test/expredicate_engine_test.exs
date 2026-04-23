defmodule ExpredicateEngineTest do
  use ExUnit.Case
  doctest Expredicate

  describe "engine selection" do
    test "new/0 creates tree with default parser engine" do
      tree = Expredicate.new()
      assert is_reference(tree)
      assert Expredicate.empty(tree)
    end

    test "new/1 with engine: :parser creates parser engine explicitly" do
      tree = Expredicate.new(engine: :parser)
      assert is_reference(tree)
      assert Expredicate.empty(tree)
    end

    test "new/1 with engine: :bytecode creates bytecode engine" do
      tree = Expredicate.new(engine: :bytecode)
      assert is_reference(tree)
      assert Expredicate.empty(tree)
    end

    test "new/1 with keyword list converts to map options" do
      tree = Expredicate.new(engine: :bytecode)
      assert is_reference(tree)
      assert Expredicate.empty(tree)
    end

    test "parser engine inserts and matches correctly" do
      tree = Expredicate.new(engine: :parser)
      {:ok, tree} = Expredicate.insert(tree, "rule1", "age > 30")
      {:ok, tree} = Expredicate.insert(tree, "rule2", "age <= 30")

      matches = Expredicate.match(tree, %{"age" => 35})
      assert Enum.sort(matches) == ["rule1"]

      matches = Expredicate.match(tree, %{"age" => 25})
      assert Enum.sort(matches) == ["rule2"]
    end

    test "bytecode engine inserts and matches correctly" do
      tree = Expredicate.new(engine: :bytecode)
      {:ok, tree} = Expredicate.insert(tree, "rule1", "age > 30")
      {:ok, tree} = Expredicate.insert(tree, "rule2", "age <= 30")

      matches = Expredicate.match(tree, %{"age" => 35})
      assert Enum.sort(matches) == ["rule1"]

      matches = Expredicate.match(tree, %{"age" => 25})
      assert Enum.sort(matches) == ["rule2"]
    end

    test "bytecode engine handles complex rules" do
      tree = Expredicate.new(engine: :bytecode)
      rule = "age > 18 and age < 65 and status == 'active'"
      {:ok, tree} = Expredicate.insert(tree, "rule1", rule)

      matches = Expredicate.match(tree, %{"age" => 30, "status" => "active"})
      assert matches == ["rule1"]

      matches = Expredicate.match(tree, %{"age" => 30, "status" => "inactive"})
      assert matches == []

      matches = Expredicate.match(tree, %{"age" => 70, "status" => "active"})
      assert matches == []
    end

    test "bytecode engine handles list membership" do
      tree = Expredicate.new(engine: :bytecode)
      rule = "brand in ['Samsung', 'LG', 'Sony']"
      {:ok, tree} = Expredicate.insert(tree, "rule1", rule)

      matches = Expredicate.match(tree, %{"brand" => "Samsung"})
      assert matches == ["rule1"]

      matches = Expredicate.match(tree, %{"brand" => "LG"})
      assert matches == ["rule1"]

      matches = Expredicate.match(tree, %{"brand" => "Apple"})
      assert matches == []
    end

    test "both engines produce identical results on the same rules" do
      rules = [
        {"r1", "age > 30"},
        {"r2", "status == 'active'"},
        {"r3", "age > 25 and status == 'active'"},
        {"r4", "score in ['A', 'B']"},
        {"r5", "not premium"}
      ]

      parser_tree   = Expredicate.new(engine: :parser)
      bytecode_tree = Expredicate.new(engine: :bytecode)

      # Insert all rules into both trees
      Enum.reduce(rules, {parser_tree, bytecode_tree}, fn {id, rule}, {p_tree, b_tree} ->
        {:ok, p_tree} = Expredicate.insert(p_tree, id, rule)
        {:ok, b_tree} = Expredicate.insert(b_tree, id, rule)
        {p_tree, b_tree}
      end)
      |> case do
        {p_tree, b_tree} ->
          test_cases = [  # Test various value maps
            %{"age" => 35, "status" => "active", "score" => "A", "premium" => false},
            %{"age" => 25, "status" => "inactive", "score" => "C", "premium" => true},
            %{"age" => 40, "status" => "active", "score" => "B", "premium" => false}
          ]

          Enum.each(test_cases, fn values ->
            p_matches = Expredicate.match(p_tree, values) |> Enum.sort()
            b_matches = Expredicate.match(b_tree, values) |> Enum.sort()

            assert p_matches == b_matches,
                   "Mismatch for values #{inspect(values)}: parser=#{inspect(p_matches)} vs bytecode=#{inspect(b_matches)}"
          end)
      end
    end

    test "engine: :invalid option defaults to parser" do
      tree = Expredicate.new(engine: :invalid)
      assert is_reference(tree)
      {:ok, tree} = Expredicate.insert(tree, "rule1", "age > 30")
      matches = Expredicate.match(tree, %{"age" => 35})
      assert matches == ["rule1"]
    end

    test "empty options map creates parser engine" do
      tree    = Expredicate.new(%{})
      assert is_reference(tree)
      {:ok, tree} = Expredicate.insert(tree, "rule1", "true")
      matches = Expredicate.match(tree, %{})
      assert matches == ["rule1"]
    end
  end
end
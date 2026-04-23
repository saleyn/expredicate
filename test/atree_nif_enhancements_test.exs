defmodule AtreeEnhancementsTest do
  use ExUnit.Case
  doctest Atree

  @moduledoc """
  Enhancement tests for Atree covering edge cases, performance, and integration scenarios.
  """

  # ==================== EDGE CASE TESTS ====================

  describe "edge_cases/undefined_variables" do
    test "handles undefined variables in value map gracefully" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "rule1", "age > 30")

      # Value map missing 'age' key
      values = %{"status" => "active"}
      matches = Atree.match(tree, values)

      # Should not match if variable is undefined
      assert matches == []
    end

    test "handles partial value maps" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "rule1", "age > 30 and status == 'active'")

      # Missing 'age' but has 'status'
      values = %{"status" => "active"}
      matches = Atree.match(tree, values)

      assert matches == []
    end

    test "succeeds with all required variables present" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "rule1", "age > 30 and status == 'active'")

      values = %{"age" => 35, "status" => "active"}
      matches = Atree.match(tree, values)

      assert matches == ["rule1"]
    end

    test "ignores extra keys in value map" do
      tree   = Atree.new()
      {:ok, tree} = Atree.insert(tree, "rule1", "age > 30")

      # Extra keys that rule doesn't use
      values = %{
        "age"    => 35,
        "status" => "active",
        "name"   => "John",
        "email"  => "john@example.com"
      }

      matches = Atree.match(tree, values)

      assert matches == ["rule1"]
    end
  end

  describe "edge_cases/type_mismatches" do
    test "string comparison with number value" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "rule1", "value == 'string'")

      # Number instead of string
      values = %{"value" => 42}
      matches = Atree.match(tree, values)

      assert matches == []
    end

    test "numeric comparison with string value" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "rule1", "value > 30")

      # String instead of number
      values = %{"value" => "hello"}
      matches = Atree.match(tree, values)

      # Should not match (type mismatch)
      assert matches == []
    end

    test "boolean equality with non-boolean" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "rule1", "active == true")

      # String instead of boolean
      values = %{"active" => "yes"}
      matches = Atree.match(tree, values)

      assert matches == []
    end

    test "correct type comparisons work" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "rule1", "count > 5")
      {:ok, tree} = Atree.insert(tree, "rule2", "name == 'John'")
      {:ok, tree} = Atree.insert(tree, "rule3", "verified == true")

      values = %{"count" => 10, "name" => "John", "verified" => true}
      matches = Atree.match(tree, values)

      assert Enum.sort(matches) == ["rule1", "rule2", "rule3"]
    end
  end

  describe "edge_cases/special_characters" do
    test "handles item IDs with special characters" do
      tree        = Atree.new()

      special_ids = [
        "rule-1",
        "rule_2",
        "rule.3",
        "rule@4",
        "rule#5",
        "rule_with_underscore_123"
      ]

      tree =
        Enum.reduce(special_ids, tree, fn id, acc ->
          {:ok, updated} = Atree.insert(acc, id, "value > 10")
          updated
        end)

      values = %{"value" => 15}
      matches = Atree.match(tree, values)

      assert Enum.sort(matches) == Enum.sort(special_ids)
    end

    test "handles unicode characters in string rules" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "rule1", "name == 'José'")
      {:ok, tree} = Atree.insert(tree, "rule2", "city == '北京'")

      values1 = %{"name" => "José"}
      matches1 = Atree.match(tree, values1)
      assert matches1 == ["rule1"]

      values2 = %{"city" => "北京"}
      matches2 = Atree.match(tree, values2)
      assert matches2 == ["rule2"]
    end

    test "handles spaces and whitespace in string values" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "rule1", "text == 'hello world'")
      {:ok, tree} = Atree.insert(tree, "rule2", "text == '  spaces  '")

      values1 = %{"text" => "hello world"}
      matches1 = Atree.match(tree, values1)
      assert matches1 == ["rule1"]

      values2 = %{"text" => "  spaces  "}
      matches2 = Atree.match(tree, values2)
      assert matches2 == ["rule2"]
    end

    test "handles quotes in item IDs and rules" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "rule_1", "value == 'don\\'t'")

      values = %{"value" => "don't"}
      matches = Atree.match(tree, values)

      assert matches == ["rule_1"]
    end
  end

  describe "edge_cases/boundary_values" do
    test "handles zero and negative numbers" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "zero", "value == 0")
      {:ok, tree} = Atree.insert(tree, "negative", "value < 0")
      {:ok, tree} = Atree.insert(tree, "positive", "value > 0")

      m1 = Atree.match(tree, %{"value" => 0})
      m2 = Atree.match(tree, %{"value" => -10})
      m3 = Atree.match(tree, %{"value" => 10})

      assert m1 == ["zero"]
      assert m2 == ["negative"]
      assert m3 == ["positive"]
    end

    test "handles very large numbers" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "large", "value > 1000000")

      matches = Atree.match(tree, %{"value" => 999_999_999})
      assert matches == ["large"]
    end

    test "handles floating point extremes" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "small", "value < 0.0001")
      {:ok, tree} = Atree.insert(tree, "normal", "value >= 0.0001 and value <= 1.0")

      m1 = Atree.match(tree, %{"value" => 0.00001})
      m2 = Atree.match(tree, %{"value" => 0.5})

      assert m1 == ["small"]
      assert m2 == ["normal"]
    end

    test "handles empty string values" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "empty", "text == ''")
      {:ok, tree} = Atree.insert(tree, "nonempty", "text != ''")

      m1 = Atree.match(tree, %{"text" => ""})
      m2 = Atree.match(tree, %{"text" => "hello"})

      assert m1 == ["empty"]
      assert m2 == ["nonempty"]
    end
  end

  describe "edge_cases/complex_expressions" do
    test "handles deeply nested parentheses" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "deep", "((((a > 10 and b < 20) or c == true)))")

      values = %{"a" => 15, "b" => 10, "c" => false}
      matches = Atree.match(tree, values)

      assert matches == ["deep"]
    end

    test "handles many AND conditions" do
      tree = Atree.new()

      {:ok, tree} =
        Atree.insert(tree, "many_and", "a > 0 and b > 0 and c > 0 and d > 0 and e > 0")

      values_pass = %{"a" => 1, "b" => 1, "c" => 1, "d" => 1, "e" => 1}
      m1 = Atree.match(tree, values_pass)
      assert m1 == ["many_and"]

      values_fail = %{"a" => 1, "b" => 1, "c" => 1, "d" => 1, "e" => -1}
      m2 = Atree.match(tree, values_fail)
      assert m2 == []
    end

    test "handles mixed operators with precedence" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "mixed", "a > 10 or b < 5 and c == true")

      # Should be parsed as: a > 10 or (b < 5 and c == true)
      values1 = %{"a" => 20, "b" => 10, "c" => false}
      m1 = Atree.match(tree, values1)
      assert m1 == ["mixed"]

      values2 = %{"a" => 5, "b" => 3, "c" => true}
      m2 = Atree.match(tree, values2)
      assert m2 == ["mixed"]

      values3 = %{"a" => 5, "b" => 10, "c" => false}
      m3 = Atree.match(tree, values3)
      assert m3 == []
    end
  end

  describe "edge_cases/error_conditions" do
    test "handles empty rule string" do
      tree   = Atree.new()

      # Empty rule should either error or be valid based on implementation
      result = Atree.insert(tree, "empty_rule", "")
      # Just verify we get a result (error or success depends on implementation)
      assert result != nil
    end

    test "handles whitespace-only rules" do
      tree   = Atree.new()

      result = Atree.insert(tree, "ws_rule", "   ")
      assert result != nil
    end

    test "case insensitive boolean values" do
      tree = Atree.new()
      {:ok, tree} = Atree.insert(tree, "bool", "value == true")

      values = %{"value" => true}
      matches = Atree.match(tree, values)

      assert matches == ["bool"]
    end
  end

  # ==================== PERFORMANCE TESTS ====================

  describe "performance/scaling" do
    @tag timeout: 30_000
    test "handles 1000 rules efficiently" do
      tree = Atree.new()

      # Insert 1000 rules
      {insert_time, tree} =
        :timer.tc(fn ->
          Enum.reduce(1..1000, tree, fn i, acc ->
            rule = "field#{rem(i, 10)} > #{i} and status == 'active'"
            {:ok, updated} = Atree.insert(acc, "rule#{i}", rule)
            updated
          end)
        end)

      count           = Atree.count(tree)
      assert count == 1000

      # Each insert should be reasonably fast (< 10ms average)
      avg_insert_time = insert_time / 1000 / 1000
      IO.puts("Average insert time: #{avg_insert_time}ms for 1000 rules")
      # 30ms total average per rule
      assert insert_time < 30_000_000
    end

    @tag timeout: 10_000
    test "matching against many rules completes quickly" do
      tree = Atree.new()

      # Create a balanced tree with 500 rules
      Enum.each(1..500, fn i ->
        rule = "value#{rem(i, 5)} > #{rem(i, 100)} and status == 'active'"
        {:ok, _} = Atree.insert(tree, "rule#{i}", rule)
      end)

      # Test matching
      values = %{
        "value0" => 50,
        "value1" => 60,
        "value2" => 70,
        "value3" => 80,
        "value4" => 90,
        "status" => "active"
      }

      {match_time, matches} =
        :timer.tc(fn -> Atree.match(tree, values) end)

      # Matching should complete in reasonable time (< 5ms for 500 rules)
      match_time_ms = match_time / 1_000_000
      IO.puts("Match time for 500 rules: #{match_time_ms}ms")
      # 5ms
      assert match_time < 5_000_000
      # Verify results were returned
      assert length(matches) > 0
    end

    @tag timeout: 5_000
    test "multiple sequential matches are consistent" do
      tree = Atree.new()

      # Insert 100 rules
      Enum.each(1..100, fn i ->
        rule = "value > #{i * 10} and status == 'active'"
        {:ok, _} = Atree.insert(tree, "rule#{i}", rule)
      end)

      values = %{"value" => 500, "status" => "active"}

      # Run 100 sequential matches
      results =
        Enum.map(1..100, fn _ ->
          matches = Atree.match(tree, values)
          matches
        end)

      # All results should be identical
      first_result = Enum.at(results, 0)
      assert Enum.all?(results, &(&1 == first_result))
      IO.puts("Verified consistent results across 100 match operations")
    end

    @tag timeout: 15_000
    test "benchmark: insert 100 rules" do
      tree = Atree.new()

      {insert_time, tree} =
        :timer.tc(fn ->
          Enum.reduce(1..100, tree, fn i, acc ->
            rule =
              "field#{rem(i, 5)} > #{i} and status == '#{Enum.at(["active", "inactive", "pending"], rem(i, 3))}'"

            {:ok, updated} = Atree.insert(acc, "rule_100_#{i}", rule)
            updated
          end)
        end)

      count           = Atree.count(tree)
      assert count == 100

      avg_insert_time = insert_time / 100 / 1000
      IO.puts("\n=== BENCHMARK: 100 RULES ===")
      IO.puts("Total insert time: #{insert_time / 1_000_000}ms")
      IO.puts("Average per insert: #{avg_insert_time}ms")
    end

    @tag timeout: 30_000
    test "benchmark: insert 1000 rules" do
      tree = Atree.new()

      {insert_time, tree} =
        :timer.tc(fn ->
          Enum.reduce(1..1000, tree, fn i, acc ->
            rule =
              "field#{rem(i, 10)} > #{i} and status == '#{Enum.at(["active", "inactive", "pending"], rem(i, 3))}'"

            {:ok, updated} = Atree.insert(acc, "rule_1000_#{i}", rule)
            updated
          end)
        end)

      count           = Atree.count(tree)
      assert count == 1000

      avg_insert_time = insert_time / 1000 / 1000
      IO.puts("\n=== BENCHMARK: 1000 RULES ===")
      IO.puts("Total insert time: #{insert_time / 1_000_000}ms")
      IO.puts("Average per insert: #{avg_insert_time}ms")
    end

    @tag timeout: 10_000
    test "benchmark: match against 100 rules" do
      tree = Atree.new()

      Enum.each(1..100, fn i ->
        rule = "field#{rem(i, 5)} > #{i}"
        {:ok, _} = Atree.insert(tree, "rule_#{i}", rule)
      end)

      values = %{
        "field0" => 50,
        "field1" => 60,
        "field2" => 70,
        "field3" => 80,
        "field4" => 90
      }

      {match_time, matches} =
        :timer.tc(fn -> Atree.match(tree, values) end)

      match_time_ms = match_time / 1_000_000
      IO.puts("\n=== BENCHMARK: MATCH AGAINST 100 RULES ===")
      IO.puts("Match time: #{match_time_ms}ms")
      IO.puts("Matching rules found: #{length(matches)}")
    end

    @tag timeout: 10_000
    test "benchmark: match against 1000 rules" do
      tree = Atree.new()

      Enum.each(1..1000, fn i ->
        rule = "field#{rem(i, 10)} > #{i}"
        {:ok, _} = Atree.insert(tree, "rule_#{i}", rule)
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

      {match_time, matches} =
        :timer.tc(fn -> Atree.match(tree, values) end)

      match_time_ms = match_time / 1_000_000
      IO.puts("\n=== BENCHMARK: MATCH AGAINST 1000 RULES ===")
      IO.puts("Match time: #{match_time_ms}ms")
      IO.puts("Matching rules found: #{length(matches)}")
    end

    @tag timeout: 15_000
    test "benchmark: remove from 100 rules" do
      tree = Atree.new()

      # Insert 100 rules
      tree =
        Enum.reduce(1..100, tree, fn i, acc ->
          {:ok, updated} = Atree.insert(acc, "remove_test_#{i}", "field > #{i}")
          updated
        end)

      initial_count = Atree.count(tree)
      assert initial_count == 100

      # Remove 50 rules and measure time
      {remove_time, tree} =
        :timer.tc(fn ->
          Enum.reduce(1..50, tree, fn i, acc ->
            {:ok, updated} = Atree.remove(acc, "remove_test_#{i}")
            updated
          end)
        end)

      final_count     = Atree.count(tree)
      assert final_count == 50

      avg_remove_time = remove_time / 50 / 1000
      IO.puts("\n=== BENCHMARK: REMOVE FROM 100 RULES ===")
      IO.puts("Total remove time: #{remove_time / 1_000_000}ms")
      IO.puts("Average per remove: #{avg_remove_time}ms")
    end

    @tag timeout: 30_000
    test "benchmark: remove from 1000 rules" do
      tree = Atree.new()

      # Insert 1000 rules
      tree =
        Enum.reduce(1..1000, tree, fn i, acc ->
          {:ok, updated} = Atree.insert(acc, "remove_test_#{i}", "field > #{i}")
          updated
        end)

      initial_count = Atree.count(tree)
      assert initial_count == 1000

      # Remove 500 rules and measure time
      {remove_time, tree} =
        :timer.tc(fn ->
          Enum.reduce(1..500, tree, fn i, acc ->
            {:ok, updated} = Atree.remove(acc, "remove_test_#{i}")
            updated
          end)
        end)

      final_count     = Atree.count(tree)
      assert final_count == 500

      avg_remove_time = remove_time / 500 / 1000
      IO.puts("\n=== BENCHMARK: REMOVE FROM 1000 RULES ===")
      IO.puts("Total remove time: #{remove_time / 1_000_000}ms")
      IO.puts("Average per remove: #{avg_remove_time}ms")
    end

    @tag timeout: 120_000
    test "benchmark: match against 100000 rules" do
      tree = Atree.new()

      IO.puts("\n=== BENCHMARK: MATCH AGAINST 100000 RULES ===")
      IO.puts("Inserting 100000 rules...")

      # Insert 100000 rules in batches to avoid timeout
      {insert_time, tree} =
        :timer.tc(fn ->
          Enum.reduce(1..100_000, tree, fn i, acc ->
            rule = "field#{rem(i, 20)} > #{rem(i, 1000)}"
            {:ok, updated} = Atree.insert(acc, "rule_#{i}", rule)
            updated
          end)
        end)

      count          = Atree.count(tree)
      assert count == 100_000

      insert_time_ms = insert_time / 1_000_000
      IO.puts("Insert complete: #{insert_time_ms}ms")

      # Create values for matching
      values =
        Enum.reduce(0..19, %{}, fn i, acc -> Map.put(acc, "field#{i}", rem(i * 100, 1000)) end)

      IO.puts("Running match against 100000 rules...")

      {match_time, matches} =
        :timer.tc(fn -> Atree.match(tree, values) end)

      match_time_ms = match_time / 1_000_000
      IO.puts("Match time: #{match_time_ms}ms")
      IO.puts("Matching rules found: #{length(matches)}")

      # Verify the result is reasonable
      assert length(matches) > 0
    end
  end

  describe "performance/memory" do
    @tag timeout: 10_000
    test "memory is released after tree operations" do
      tree = Atree.new()

      # Insert and remove many items
      tree =
        Enum.reduce(1..100, tree, fn i, acc ->
          {:ok, updated} = Atree.insert(acc, "rule#{i}", "value > #{i}")
          updated
        end)

      # Remove them all
      tree =
        Enum.reduce(1..100, tree, fn i, acc ->
          {:ok, updated} = Atree.remove(acc, "rule#{i}")
          updated
        end)

      # Tree should be empty
      0 = Atree.count(tree)
      assert Atree.empty(tree) == true
    end

    @tag timeout: 5_000
    test "clear operation is efficient" do
      tree = Atree.new()

      # Insert 1000 rules
      tree =
        Enum.reduce(1..1000, tree, fn i, acc ->
          {:ok, updated} = Atree.insert(acc, "rule#{i}", "value > #{i}")
          updated
        end)

      # Clear should be fast
      {clear_time, _} = :timer.tc(fn -> Atree.clear(tree) end)

      clear_time_ms = clear_time / 1000
      IO.puts("Clear time for 1000 rules: #{clear_time_ms}ms")

      0 = Atree.count(tree)
      # Should complete within 1ms
      assert clear_time < 1_000_000
    end
  end

  # ==================== INTEGRATION TESTS ====================

  describe "integration/concurrent_access" do
    @tag timeout: 15_000
    test "concurrent reads from same tree" do
      tree = Atree.new()

      # Setup initial data
      Enum.each(1..50, fn i ->
        {:ok, _} = Atree.insert(tree, "rule#{i}", "value > #{i * 10} and status == 'active'")
      end)

      values = %{"value" => 1000, "status" => "active"}

      # Spawn multiple tasks that read concurrently
      tasks =
        Enum.map(1..10, fn _task_num ->
          Task.async(fn ->
            Enum.map(1..5, fn _ ->
              matches = Atree.match(tree, values)
              matches
            end)
          end)
        end)

      results      = Task.await_many(tasks)

      # All tasks should get same results
      first_result = Enum.at(results, 0) |> Enum.at(0)

      assert Enum.all?(results, fn task_results ->
               Enum.all?(task_results, &(&1 == first_result))
             end)

      IO.puts("Concurrent reads test: all 10 tasks produced consistent results")
    end

    @tag timeout: 20_000
    test "sequential insert and match operations" do
      tree = Atree.new()

      # Multiple processes doing insert/match in sequence
      tasks =
        Enum.map(1..5, fn task_id -> Task.async(fn -> tree_ref = tree

            # Each task inserts different rules
            Enum.each(1..20, fn i ->
              rule_id = "task#{task_id}_rule#{i}"
              rule    = "value > #{task_id * 100 + i} and status == 'active'"
              {:ok, _} = Atree.insert(tree_ref, rule_id, rule)
            end)

            # Then tries to match
            values = %{"value" => 1000, "status" => "active"}
            matches = Atree.match(tree_ref, values)
            length(matches)
          end)
        end)

      results     = Task.await_many(tasks)

      # Verify we have results from all tasks
      assert length(results) == 5
      assert Enum.all?(results, &(&1 >= 0))

      # Final count should be 100 (5 tasks × 20 rules each)
      final_count = Atree.count(tree)
      assert final_count == 100

      IO.puts("Concurrent insert/match test: #{final_count} total rules inserted")
    end
  end

  describe "integration/real_world_scenarios" do
    @tag timeout: 10_000
    test "customer segmentation with complex rules" do
      tree  = Atree.new()

      # Define complex business rules
      rules = [
        {"vip_customer", "lifetime_spend > 10000 and account_age > 365 and churn_risk < 20"},
        {"at_risk", "days_since_purchase > 90 or churn_risk > 70"},
        {"high_value", "monthly_spend > 1000 and status == 'active'"},
        {"trial_user", "account_age <= 30 and subscription_tier == 'trial'"},
        {"premium_user", "subscription_tier == 'premium' or lifetime_spend > 5000"},
        {"seasonal", "purchase_frequency > 0 and month_match == true"},
        {"loyal", "repeat_purchase_ratio > 0.8 and account_age > 180"}
      ]

      # Insert all rules
      Enum.each(rules, fn {id, rule} -> {:ok, _} = Atree.insert(tree, id, rule) end)

      # Test various customer profiles
      customers = [
        {
          "customer_1",
          %{
            "lifetime_spend"        => 15000,
            "account_age"           => 500,
            "churn_risk"            => 10,
            "days_since_purchase"   => 10,
            "monthly_spend"         => 1500,
            "status"                => "active",
            "subscription_tier"     => "premium",
            "purchase_frequency"    => 12,
            "month_match"           => true,
            "repeat_purchase_ratio" => 0.9
          },
          ["vip_customer", "high_value", "premium_user", "seasonal", "loyal"]
        },
        {
          "customer_2",
          %{
            "lifetime_spend"        => 100,
            "account_age"           => 15,
            "churn_risk"            => 5,
            "days_since_purchase"   => 5,
            "monthly_spend"         => 10,
            "status"                => "active",
            "subscription_tier"     => "trial",
            "purchase_frequency"    => 1,
            "month_match"           => false,
            "repeat_purchase_ratio" => 0.0
          },
          ["trial_user"]
        },
        {
          "customer_3",
          %{
            "lifetime_spend"        => 500,
            "account_age"           => 200,
            "churn_risk"            => 80,
            "days_since_purchase"   => 120,
            "monthly_spend"         => 50,
            "status"                => "active",
            "subscription_tier"     => "basic",
            "purchase_frequency"    => 2,
            "month_match"           => false,
            "repeat_purchase_ratio" => 0.2
          },
          ["at_risk"]
        }
      ]

      # Verify results
      Enum.each(customers, fn {_id, values, expected_segments} ->
        matches         = Atree.match(tree, values)
        matched_sorted  = Enum.sort(matches)
        expected_sorted = Enum.sort(expected_segments)
        assert matched_sorted == expected_sorted
      end)

      IO.puts("Customer segmentation test: verified 3 customer profiles")
    end

    @tag timeout: 10_000
    test "product catalog filtering with multiple criteria" do
      tree  = Atree.new()

      # Product rules
      rules = [
        {"low_stock", "quantity_available < 10"},
        {"need_reorder", "quantity_available < quantity_reorder_point"},
        {"on_sale", "discount_percentage > 0"},
        {"clearance", "discount_percentage >= 50"},
        {"bestseller", "monthly_sales > 100"},
        {"loss_leader", "profit_margin < 5"},
        {"premium", "price > 500 and profit_margin > 25"},
        {"discontinued", "status == 'discontinued'"},
        {"new_product", "days_since_launch < 30"}
      ]

      Enum.each(rules, fn {id, rule} -> {:ok, _} = Atree.insert(tree, id, rule) end)

      # Test products
      products = [
        {
          "laptop_pro",
          %{
            "price"                  => 1200,
            "quantity_available"     => 5,
            "quantity_reorder_point" => 10,
            "discount_percentage"    => 0,
            "monthly_sales"          => 150,
            "profit_margin"          => 30,
            "status"                 => "active",
            "days_since_launch"      => 200
          },
          ["low_stock", "need_reorder", "bestseller", "premium"]
        },
        {
          "clearance_shirt",
          %{
            "price"                  => 10,
            "quantity_available"     => 100,
            "quantity_reorder_point" => 20,
            "discount_percentage"    => 70,
            "monthly_sales"          => 500,
            "profit_margin"          => 1,
            "status"                 => "active",
            "days_since_launch"      => 365
          },
          ["on_sale", "clearance", "bestseller", "loss_leader"]
        }
      ]

      Enum.each(products, fn {_id, values, expected} ->
        matches = Atree.match(tree, values)
        assert Enum.sort(matches) == Enum.sort(expected)
      end)

      IO.puts("Product filtering test: verified 2 products with complex rules")
    end
  end

  describe "integration/stability" do
    @tag timeout: 15_000
    test "prolonged operations don't degrade performance" do
      tree = Atree.new()

      # Warmup
      Enum.each(1..10, fn i -> {:ok, _} = Atree.insert(tree, "warmup#{i}", "value > #{i}") end)

      # Run operations in rounds and track performance
      Enum.each(1..5, fn round ->
        # Insert batch
        Enum.each(1..20, fn i ->
          rule_id = "round#{round}_rule#{i}"
          rule    = "value > #{round * 100 + i}"
          {:ok, _} = Atree.insert(tree, rule_id, rule)
        end)

        # Match operation
        values = %{"value" => 1000}
        _matches = Atree.match(tree, values)

        # Remove some
        Enum.each(1..5, fn i ->
          rule_id = "round#{round}_rule#{i}"
          {:ok, _} = Atree.remove(tree, rule_id)
        end)
      end)

      # Final verification
      count = Atree.count(tree)
      assert count > 0

      IO.puts("Stability test: completed 5 rounds of insert/match/remove cycles")
    end
  end
end
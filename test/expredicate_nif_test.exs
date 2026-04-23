defmodule ExpredicateTest do
  use ExUnit.Case
  doctest Expredicate

  describe "new/0" do
    test "creates a new rule tree" do
      tree = Expredicate.new()
      assert is_reference(tree)
    end
  end

  describe "insert/3" do
    test "inserts a rule successfully" do
      tree = Expredicate.new()
      {:ok, returned_tree} = Expredicate.insert(tree, "rule1", "age > 30")
      assert is_reference(returned_tree)
    end

    test "returns error for duplicate item ID" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "item1", "age > 30")
      {:error, :item_exists} = Expredicate.insert(tree, "item1", "age < 50")
    end

    test "inserts different item IDs with same rule" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "item1", "age > 30")
      {:ok, tree} = Expredicate.insert(tree, "item2", "age > 30")
      2 = Expredicate.count(tree)
    end

    test "accepts various rule formats" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "r1", "age > 30")
      {:ok, tree} = Expredicate.insert(tree, "r2", "status == 'active'")
      {:ok, tree} = Expredicate.insert(tree, "r3", "status != 'deleted'")
      {:ok, tree} = Expredicate.insert(tree, "r4", "age > 30 and status == 'active'")
      {:ok, tree} = Expredicate.insert(tree, "r5", "age < 25 or premium == true")
      {:ok, tree} = Expredicate.insert(tree, "r6", "brand in ['Apple', 'Samsung']")
      6 = Expredicate.count(tree)
    end
  end

  describe "match/2" do
    setup do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "under_30", "age < 30")
      {:ok, tree} = Expredicate.insert(tree, "over_30", "age > 30")
      {:ok, tree} = Expredicate.insert(tree, "active", "status == 'active'")
      {:ok, tree} = Expredicate.insert(tree, "premium", "status == 'premium'")
      [tree: tree]
    end

    test "matches rules against value map", %{tree: tree} do
      values = %{"age" => 35, "status" => "active"}
      matches = Expredicate.match(tree, values)
      assert Enum.sort(matches) == ["active", "over_30"]
    end

    test "returns empty list when no rules match", %{tree: tree} do
      values = %{"age" => 30, "status" => "inactive"}
      matches = Expredicate.match(tree, values)
      assert matches == []
    end

    test "matches all rules" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "r1", "age > 30")
      {:ok, tree} = Expredicate.insert(tree, "r2", "age > 25")
      {:ok, tree} = Expredicate.insert(tree, "r3", "age > 20")
      matches = Expredicate.match(tree, %{"age" => 40})
      assert Enum.sort(matches) == ["r1", "r2", "r3"]
    end

    test "handles string values" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "samsung", "brand == 'Samsung'")
      {:ok, tree} = Expredicate.insert(tree, "lg", "brand == 'LG'")
      matches = Expredicate.match(tree, %{"brand" => "Samsung"})
      assert matches == ["samsung"]
    end

    test "handles boolean values" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "premium", "is_premium == true")
      {:ok, tree} = Expredicate.insert(tree, "not_premium", "is_premium == false")
      matches = Expredicate.match(tree, %{"is_premium" => true})
      assert matches == ["premium"]
    end

    test "handles floating point comparisons" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "high", "rating > 4.5")
      {:ok, tree} = Expredicate.insert(tree, "medium", "rating > 3.0")
      matches = Expredicate.match(tree, %{"rating" => 4.7})
      assert Enum.sort(matches) == ["high", "medium"]
    end
  end

  describe "remove/2" do
    test "removes an existing item" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "item1", "age > 30")
      {:ok, tree} = Expredicate.remove(tree, "item1")
      0 = Expredicate.count(tree)
    end

    test "returns error for non-existent item" do
      tree = Expredicate.new()
      {:error, :not_found} = Expredicate.remove(tree, "nonexistent")
    end

    test "can reinsert after removal" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "item1", "age > 30")
      {:ok, tree} = Expredicate.remove(tree, "item1")
      {:ok, tree} = Expredicate.insert(tree, "item1", "age < 25")
      1 = Expredicate.count(tree)
    end
  end

  describe "logical operators" do
    test "matches AND operator" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "match", "age > 30 and status == 'active'")

      matches1 = Expredicate.match(tree, %{"age" => 40, "status" => "active"})
      assert matches1 == ["match"]

      matches2 = Expredicate.match(tree, %{"age" => 40, "status" => "inactive"})
      assert matches2 == []

      matches3 = Expredicate.match(tree, %{"age" => 20, "status" => "active"})
      assert matches3 == []
    end

    test "matches OR operator" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "match", "status == 'vip' or balance > 5000")

      matches1 = Expredicate.match(tree, %{"status" => "vip", "balance" => 100})
      assert matches1 == ["match"]

      matches2 = Expredicate.match(tree, %{"status" => "regular", "balance" => 6000})
      assert matches2 == ["match"]

      matches3 = Expredicate.match(tree, %{"status" => "regular", "balance" => 100})
      assert matches3 == []
    end

    test "matches NOT operator" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "match", "not suspended")

      matches1 = Expredicate.match(tree, %{"suspended" => false})
      assert matches1 == ["match"]

      matches2 = Expredicate.match(tree, %{"suspended" => true})
      assert matches2 == []
    end

    test "matches IN operator" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "match", "brand in ['Apple', 'Samsung']")

      matches1 = Expredicate.match(tree, %{"brand" => "Apple"})
      assert matches1 == ["match"]

      matches2 = Expredicate.match(tree, %{"brand" => "Samsung"})
      assert matches2 == ["match"]

      matches3 = Expredicate.match(tree, %{"brand" => "LG"})
      assert matches3 == []
    end

    test "matches NOT IN operator" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "not_apple", "brand not in ['Apple', 'Samsung']")

      matches1 = Expredicate.match(tree, %{"brand" => "LG"})
      assert matches1 == ["not_apple"]

      matches2 = Expredicate.match(tree, %{"brand" => "Google"})
      assert matches2 == ["not_apple"]

      matches3 = Expredicate.match(tree, %{"brand" => "Apple"})
      assert matches3 == []

      matches4 = Expredicate.match(tree, %{"brand" => "Samsung"})
      assert matches4 == []
    end

    test "combines IN and NOT IN in same rule set" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "premium_brands", "brand in ['Apple', 'Samsung']")
      {:ok, tree} = Expredicate.insert(tree, "budget_brands", "brand not in ['Apple', 'Samsung']")

      matches1 = Expredicate.match(tree, %{"brand" => "Apple"})
      assert matches1 == ["premium_brands"]

      matches2 = Expredicate.match(tree, %{"brand" => "LG"})
      assert matches2 == ["budget_brands"]
    end

    test "NOT IN with numeric values" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "exclude_low", "rating not in ['1', '2', '3']")

      matches1 = Expredicate.match(tree, %{"rating" => 4})
      assert matches1 == ["exclude_low"]

      matches2 = Expredicate.match(tree, %{"rating" => 5})
      assert matches2 == ["exclude_low"]

      matches3 = Expredicate.match(tree, %{"rating" => 2})
      assert matches3 == []
    end

    test "handles complex expressions" do
      tree = Expredicate.new()

      {:ok, tree} =
        Expredicate.insert(tree, "match", "(age > 30 and age < 65) and status == 'employed'")

      matches1 = Expredicate.match(tree, %{"age" => 45, "status" => "employed"})
      assert matches1 == ["match"]

      matches2 = Expredicate.match(tree, %{"age" => 25, "status" => "employed"})
      assert matches2 == []
    end
  end

  describe "all_items/1" do
    test "returns all item IDs" do
      tree  = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "a", "age > 30")
      {:ok, tree} = Expredicate.insert(tree, "b", "age < 25")
      {:ok, tree} = Expredicate.insert(tree, "c", "age == 30")
      items = Expredicate.all_items(tree)
      assert Enum.sort(items) == ["a", "b", "c"]
    end

    test "returns empty list for empty tree" do
      tree  = Expredicate.new()
      items = Expredicate.all_items(tree)
      assert items == []
    end
  end

  describe "count/1" do
    test "returns 0 for empty tree" do
      tree = Expredicate.new()
      0 = Expredicate.count(tree)
    end

    test "returns correct count" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "a", "true")
      {:ok, tree} = Expredicate.insert(tree, "b", "true")
      {:ok, tree} = Expredicate.insert(tree, "c", "true")
      3 = Expredicate.count(tree)
    end

    test "decreases after removal" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "a", "true")
      {:ok, tree} = Expredicate.insert(tree, "b", "true")
      {:ok, tree} = Expredicate.remove(tree, "a")
      1 = Expredicate.count(tree)
    end
  end

  describe "clear/1" do
    test "clears all items" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "a", "true")
      {:ok, tree} = Expredicate.insert(tree, "b", "true")
      :ok = Expredicate.clear(tree)
      0 = Expredicate.count(tree)
    end
  end

  describe "empty/1" do
    test "returns true for empty tree" do
      tree = Expredicate.new()
      assert Expredicate.empty(tree) == true
    end

    test "returns false for non-empty tree" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "a", "true")
      assert Expredicate.empty(tree) == false
    end

    test "returns true after clearing" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "a", "true")
      :ok = Expredicate.clear(tree)
      assert Expredicate.empty(tree) == true
    end
  end

  describe "exists/2" do
    test "returns true for existing item" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "item1", "age > 30")
      assert Expredicate.exists(tree, "item1") == true
    end

    test "returns false for non-existent item" do
      tree = Expredicate.new()
      assert Expredicate.exists(tree, "nonexistent") == false
    end

    test "returns false after removal" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "item1", "age > 30")
      {:ok, tree} = Expredicate.remove(tree, "item1")
      assert Expredicate.exists(tree, "item1") == false
    end
  end

  describe "comparison operators" do
    test "greater than operator" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "r", "value > 10")
      m1 = Expredicate.match(tree, %{"value" => 15})
      m2 = Expredicate.match(tree, %{"value" => 10})
      m3 = Expredicate.match(tree, %{"value" => 5})
      assert m1 == ["r"] and m2 == [] and m3 == []
    end

    test "less than operator" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "r", "value < 10")
      m1 = Expredicate.match(tree, %{"value" => 5})
      m2 = Expredicate.match(tree, %{"value" => 10})
      m3 = Expredicate.match(tree, %{"value" => 15})
      assert m1 == ["r"] and m2 == [] and m3 == []
    end

    test "greater or equal operator" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "r", "value >= 10")
      m1 = Expredicate.match(tree, %{"value" => 15})
      m2 = Expredicate.match(tree, %{"value" => 10})
      m3 = Expredicate.match(tree, %{"value" => 5})
      assert m1 == ["r"] and m2 == ["r"] and m3 == []
    end

    test "less or equal operator" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "r", "value <= 10")
      m1 = Expredicate.match(tree, %{"value" => 5})
      m2 = Expredicate.match(tree, %{"value" => 10})
      m3 = Expredicate.match(tree, %{"value" => 15})
      assert m1 == ["r"] and m2 == ["r"] and m3 == []
    end

    test "not equal operator" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "r", "status != 'deleted'")
      m1 = Expredicate.match(tree, %{"status" => "active"})
      m2 = Expredicate.match(tree, %{"status" => "deleted"})
      assert m1 == ["r"] and m2 == []
    end
  end

  describe "int64_t support" do
    test "parses and matches integer literals" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "r1", "count == 42")
      {:ok, tree} = Expredicate.insert(tree, "r2", "count > 40")

      matches1 = Expredicate.match(tree, %{"count" => 42})
      assert Enum.sort(matches1) == ["r1", "r2"]

      matches2 = Expredicate.match(tree, %{"count" => 50})
      assert matches2 == ["r2"]

      matches3 = Expredicate.match(tree, %{"count" => 30})
      assert matches3 == []
    end

    test "handles large int64_t values" do
      tree      = Expredicate.new()
      # max int64
      large_num = 9_223_372_036_854_775_807
      {:ok, tree} = Expredicate.insert(tree, "r1", "value == 9223372036854775807")
      {:ok, tree} = Expredicate.insert(tree, "r2", "value > 9000000000000000000")

      matches1 = Expredicate.match(tree, %{"value" => large_num})
      assert Enum.sort(matches1) == ["r1", "r2"]
    end

    test "handles negative int64_t values" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "r1", "temp == -40")
      {:ok, tree} = Expredicate.insert(tree, "r2", "temp < -30")

      matches1 = Expredicate.match(tree, %{"temp" => -40})
      assert Enum.sort(matches1) == ["r1", "r2"]

      matches2 = Expredicate.match(tree, %{"temp" => -35})
      assert matches2 == ["r2"]

      matches3 = Expredicate.match(tree, %{"temp" => 0})
      assert matches3 == []
    end

    test "compares int64_t with double" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "higher", "value > 50")

      # int64
      matches1 = Expredicate.match(tree, %{"value" => 100})
      # double
      matches2 = Expredicate.match(tree, %{"value" => 100.5})
      # int64
      matches3 = Expredicate.match(tree, %{"value" => 25})

      assert matches1 == ["higher"]
      assert matches2 == ["higher"]
      assert matches3 == []
    end

    test "int64_t equality with mixed numeric types" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "exact", "level == 10")

      # Test int64_t matching
      matches1 = Expredicate.match(tree, %{"level" => 10})
      assert matches1 == ["exact"]

      # Test with double that's equivalent
      matches2 = Expredicate.match(tree, %{"level" => 10.0})
      assert matches2 == ["exact"]

      # Test non-matching
      matches3 = Expredicate.match(tree, %{"level" => 11})
      assert matches3 == []
    end

    test "int64_t with comparison operators" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "eq", "x == 5")
      {:ok, tree} = Expredicate.insert(tree, "ne", "x != 5")
      {:ok, tree} = Expredicate.insert(tree, "lt", "x < 5")
      {:ok, tree} = Expredicate.insert(tree, "le", "x <= 5")
      {:ok, tree} = Expredicate.insert(tree, "gt", "x > 5")
      {:ok, tree} = Expredicate.insert(tree, "ge", "x >= 5")

      matches = Expredicate.match(tree, %{"x" => 5})
      # At 5: eq, ne, le, ge should match (not lt, not gt)
      assert "eq" in matches
      assert "le" in matches
      assert "ge" in matches
      assert "lt" not in matches
      assert "gt" not in matches
    end

    test "int64_t truthiness in logical expressions" do
      tree = Expredicate.new()
      # non-zero int is truthy
      {:ok, tree} = Expredicate.insert(tree, "truthy", "count")
      # zero int is falsy
      {:ok, tree} = Expredicate.insert(tree, "falsy", "not count")

      matches1 = Expredicate.match(tree, %{"count" => 1})
      assert matches1 == ["truthy"]

      matches2 = Expredicate.match(tree, %{"count" => 0})
      assert matches2 == ["falsy"]

      matches3 = Expredicate.match(tree, %{"count" => -1})
      assert matches3 == ["truthy"]
    end

    test "int64_t in complex logical expressions" do
      tree = Expredicate.new()
      {:ok, tree} = Expredicate.insert(tree, "complex", "age > 18 and score >= 100")

      matches1 = Expredicate.match(tree, %{"age" => 25, "score" => 150})
      assert matches1 == ["complex"]

      matches2 = Expredicate.match(tree, %{"age" => 25, "score" => 50})
      assert matches2 == []

      matches3 = Expredicate.match(tree, %{"age" => 15, "score" => 150})
      assert matches3 == []
    end
  end
end
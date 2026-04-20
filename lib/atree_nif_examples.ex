defmodule Atree.Examples do
  @moduledoc """
  Example usage of the Atree rule matching engine.
  """

  # Suppress compiler warnings for this module
  # NIF functions have @spec declarations but their implementations raise "NIF not loaded"
  # since they're replaced at runtime via @on_load. This causes false positive warnings
  # from flow-sensitive type checking. The functions work correctly at runtime.
  @compile   :no_warn_undefined

  @doc       """
  Simple example of rule-based matching.
  """
  def simple_example do
    IO.puts("=== Rule-Based Matching Example ===\n")

    # Create a new tree
    tree = Atree.new()

    IO.puts("Created new rule tree")

    # Define some rules
    rules = %{
      "premium_customer" => "status == 'premium' and age >= 18",
      "young_audience"   => "age < 25",
      "samsung_user"     => "tv_brand in ['Samsung', 'samsung']",
      "active_adult"     => "status == 'active' and age > 30 and age <= 65"
    }

    # Insert rules
    Enum.reduce(rules, tree, fn {item_id, rule}, acc ->
      {:ok, updated} = Atree.insert(acc, item_id, rule)
      IO.puts("  Inserted rule: #{item_id}")
      updated
    end)

    IO.puts("")

    # Test with different value maps
    test_cases = [
      %{
        "status"   => "premium",
        "age"      => 35,
        "tv_brand" => "Samsung"
      },
      %{
        "status"   => "active",
        "age"      => 22,
        "tv_brand" => "LG"
      },
      %{
        "status"   => "pending",
        "age"      => 45,
        "tv_brand" => "Sony"
      }
    ]

    Enum.each(test_cases, fn values ->
      matches = Atree.match(tree, values)

      IO.puts("Values: #{inspect(values)}")
      IO.puts("Matching rules: #{Enum.join(matches, ", ") || "(none)"}")
      IO.puts("")
    end)
  end

  @doc """
  Example with inventory filtering rules.
  """
  def inventory_filtering_example do
    IO.puts("=== Inventory Filtering Example ===\n")

    tree = Atree.new()

    # Define product rules
    rules = %{
      "must_reorder"    => "stock < 10",
      "on_sale"         => "discount_percentage > 0",
      "clearance"       => "discount_percentage >= 50",
      "popular_item"    => "monthly_sales > 100",
      "low_margin"      => "profit_margin < 10",
      "premium_product" => "price > 500 and profit_margin > 30"
    }

    Enum.each(rules, fn {item_id, rule} -> {:ok, _} = Atree.insert(tree, item_id, rule) end)

    # Inventory items
    items = [
      {"laptop_1",
       %{
         "stock"               => 5,
         "price"               => 800,
         "discount_percentage" => 0,
         "monthly_sales"       => 50,
         "profit_margin"       => 35
       }},
      {"shirt_1",
       %{
         "stock"               => 50,
         "price"               => 25,
         "discount_percentage" => 30,
         "monthly_sales"       => 500,
         "profit_margin"       => 8
       }},
      {"phone_1",
       %{
         "stock"               => 2,
         "price"               => 600,
         "discount_percentage" => 50,
         "monthly_sales"       => 200,
         "profit_margin"       => 25
       }}
    ]

    Enum.each(items, fn {item_name, values} ->
      matches = Atree.match(tree, values)
      IO.puts("#{item_name}:")
      IO.puts("  Values: #{inspect(values, pretty: true)}")
      IO.puts("  Triggered rules: #{Enum.join(matches, ", ") || "(none)"}")
      IO.puts("")
    end)
  end

  @doc """
  Example with user segmentation rules.
  """
  def user_segmentation_example do
    IO.puts("=== User Segmentation Example ===\n")

    tree = Atree.new()

    # Define user segments
    segments = %{
      "vip"                => "lifetime_spend > 10000 and account_age > 365",
      "churned"            => "days_since_login > 90",
      "engaged"            => "login_count > 50 and days_since_login < 7",
      "trial"              => "account_age <= 30 and status == 'trial'",
      "premium_subscriber" => "subscription_tier == 'premium' or lifetime_spend > 5000"
    }

    Enum.each(segments, fn {segment_id, rule} ->
      {:ok, _} = Atree.insert(tree, segment_id, rule)
    end)

    # Example users
    users = [
      {"user_1000",
       %{
         "lifetime_spend"    => 15000,
         "account_age"       => 500,
         "days_since_login"  => 2,
         "login_count"       => 150,
         "status"            => "active",
         "subscription_tier" => "premium"
       }},
      {"user_2000",
       %{
         "lifetime_spend"    => 100,
         "account_age"       => 10,
         "days_since_login"  => 2,
         "login_count"       => 5,
         "status"            => "trial",
         "subscription_tier" => "trial"
       }},
      {"user_3000",
       %{
         "lifetime_spend"    => 500,
         "account_age"       => 400,
         "days_since_login"  => 120,
         "login_count"       => 10,
         "status"            => "inactive",
         "subscription_tier" => "free"
       }}
    ]

    Enum.each(users, fn {user_id, values} ->
      matches = Atree.match(tree, values)
      segments_str = Enum.join(matches, ", ") || "(not segmented)"
      IO.puts("#{user_id}: #{segments_str}")
    end)

    IO.puts("")
  end

  @doc """
  Benchmark example comparing matching performance.
  """
  def benchmark_example do
    IO.puts("=== Rule Matching Benchmark ===\n")

    tree = Atree.new()

    # Create many rules
    num_rules = 100
    IO.write("Creating #{num_rules} rules... ")

    {insert_time, _} =
      :timer.tc(fn ->
        Enum.each(1..num_rules, fn i ->
          rule = "field#{rem(i, 10)} > #{i * 10} and status == 'active'"
          {:ok, _} = Atree.insert(tree, "rule#{i}", rule)
        end)
      end)

    IO.puts("done (#{insert_time / 1000}ms)\n")

    # Test matching
    count = Atree.count(tree)
    IO.puts("Total rules: #{count}\n")

    # Benchmark matching with different value maps
    test_values = [
      %{"field0" => 150, "status" => "active"},
      %{"field5" => 250, "status" => "inactive"},
      %{"field9" => 450, "status" => "active"}
    ]

    Enum.each(test_values, fn values ->
      {match_time, matches} =
        :timer.tc(fn -> Atree.match(tree, values) end)

      percent = (length(matches) / count * 100) |> Float.round(1)
      IO.puts("Values: #{inspect(values)}")
      IO.puts("  Query time: #{match_time}μs")
      IO.puts("  Matches: #{length(matches)}/#{count} (#{percent}%)")
      IO.puts("")
    end)
  end

  @doc """
  Example demonstrating all rule operators.
  """
  def operators_example do
    IO.puts("=== Operators and Rule Syntax ===\n")

    tree = Atree.new()

    examples = [
      {"greater_than", "value > 100"},
      {"less_than", "value < 50"},
      {"greater_equal", "value >= 100"},
      {"less_equal", "value <= 100"},
      {"equal", "status == 'active'"},
      {"not_equal", "status != 'deleted'"},
      {"logical_and", "age > 30 and status == 'active'"},
      {"logical_or", "status == 'vip' or balance > 5000"},
      {"logical_not", "not suspended"},
      {"in_list", "brand in ['Apple', 'Samsung', 'LG']"},
      {"complex", "(age > 30 and age < 65) and status == 'employed'"}
    ]

    Enum.each(examples, fn {name, rule} ->
      {:ok, _} = Atree.insert(tree, name, rule)
      IO.puts("#{name}: #{rule}")
    end)

    IO.puts("")
    IO.puts("Test matching:")

    test_values = %{
      "value"     => 150,
      "status"    => "active",
      "age"       => 45,
      "suspended" => false,
      "balance"   => 3000,
      "brand"     => "Samsung"
    }

    matches = Atree.match(tree, test_values)
    IO.puts("Input: #{inspect(test_values, pretty: true)}")
    IO.puts("Matching rules: #{Enum.join(Enum.sort(matches), ", ")}")
  end
end

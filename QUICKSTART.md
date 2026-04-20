# Quick Start Guide

## Setup & Installation

### 1. Verify Prerequisites

```bash
# Check Erlang is installed
erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().'

# Check Elixir is installed
elixir --version

# Check C++ compiler
g++ --version  # or clang++ --version

# Check Make
make --version
```

### 2. Navigate to Project

```bash
cd /home/serge/projects/atree-nif
```

### 3. Generate Dependencies

```bash
# Install Elixir dependencies
mix deps.get

# Format code (optional)
mix format
```

### 4. Compile the Project

```bash
# This will compile both C++ and Elixir code
mix compile
```

If compilation succeeds, you should see:
```
Compiling C extensions...
Compiling 2 files (.ex)
Generated atree_nif app
```

## Running Tests

```bash
# Run all tests
mix test

# Run with verbose output
mix test --trace

# Run specific test file
mix test test/atree_nif_test.exs
```

Expected output:
```
Compiling C extensions...
Compiling 2 files (.ex)
Generating Atree app
.....................................................

Finished in X.XXs
53 tests, 0 failures
```

## Interactive Usage (IEx)

```bash
# Start interactive Elixir shell
iex -S mix
```

In the shell:

```elixir
# Create a new rule tree
iex> {:ok, tree} = Atree.new()
{:ok, #Reference<0.123456789.0.0>}

# Insert items with rules
iex> {:ok, tree} = Atree.insert(tree, "rule1", "age > 30")
{:ok, #Reference<0.123456789.0.0>}

iex> {:ok, tree} = Atree.insert(tree, "rule2", "status == 'active'")
{:ok, #Reference<0.123456789.0.0>}

# Match a value map against all rules
iex> {:ok, matched} = Atree.match(tree, %{"age" => 35, "status" => "active"})
{:ok, ["rule1", "rule2"]}

# Check if an item exists
iex> {:ok, true} = Atree.exists(tree, "rule1")

# Get all items
iex> {:ok, items} = Atree.all_items(tree)
{:ok, ["rule1", "rule2"]}

# Get count
iex> {:ok, 2} = Atree.count(tree)

# Remove an item
iex> {:ok, tree} = Atree.remove(tree, "rule1")

# Clear the tree
iex> :ok = Atree.clear(tree)

# Check if empty
iex> {:ok, true} = Atree.empty(tree)
```

## Run Examples

```bash
# In iex shell
iex> Atree.Examples.simple_example()
=== Rule-Based Matching Example ===

Created new rule tree
  Inserted rule: premium_customer
  Inserted rule: young_audience
  Inserted rule: samsung_user
  Inserted rule: active_adult

Values: %{...}
Matching rules: ...

# More examples
iex> Atree.Examples.inventory_filtering_example()
iex> Atree.Examples.user_segmentation_example()
iex> Atree.Examples.benchmark_example()
iex> Atree.Examples.operators_example()
```

## Rule Syntax Examples

### Simple Comparisons

```elixir
# Greater than / less than
"age > 30"
"balance < 1000"
"rating >= 4.5"

# Equality
"status == 'active'"
"status != 'deleted'"

# String values
"brand == 'Samsung'"
"color != 'red'"
```

### Logical Operators

```elixir
# AND - both must be true
"age > 30 and status == 'active'"
"balance > 1000 and verified == true"

# OR - at least one must be true
"premium == true or balance > 5000"
"status == 'vip' or status == 'employee'"

# NOT - negation
"not suspended"
"not (age < 18)"
```

### List Membership

```elixir
# IN - check if value is in a list
"brand in ['Apple', 'Samsung', 'LG']"
"status in ['active', 'pending', 'vip']"
"color in ['red', 'blue', 'green']"
```

### Complex Expressions

```elixir
# Grouping with parentheses
"(age > 18 and age < 65) and status == 'employed'"

# Mix operators
"(status == 'premium' or lifetime_spend > 10000) and not suspended"
"not deleted and (status == 'active' or days_since_login < 30)"
```

## Practical Examples

### User Segmentation

```elixir
{:ok, tree} = Atree.new()

# Define segments
{:ok, tree} = Atree.insert(tree, "vip", "lifetime_spend > 10000")
{:ok, tree} = Atree.insert(tree, "engaged", "login_count > 50")
{:ok, tree} = Atree.insert(tree, "churned", "days_since_login > 90")

# Check user
user = %{
  "lifetime_spend" => 15000,
  "login_count" => 100,
  "days_since_login" => 5
}

{:ok, segments} = Atree.match(tree, user)
# => {:ok, ["vip", "engaged"]}
```

### Product Filtering

```elixir
{:ok, tree} = Atree.new()

{:ok, tree} = Atree.insert(tree, "low_stock", "quantity < 10")
{:ok, tree} = Atree.insert(tree, "on_sale", "discount > 0")
{:ok, tree} = Atree.insert(tree, "expensive", "price > 500")

product = %{"quantity" => 5, "discount" => 25, "price" => 600}

{:ok, tags} = Atree.match(tree, product)
# => {:ok, ["low_stock", "on_sale", "expensive"]}
```

### Access Control

```elixir
{:ok, tree} = Atree.new()

{:ok, tree} = Atree.insert(tree, "admin", "role == 'admin'")
{:ok, tree} = Atree.insert(tree, "manager", "role == 'manager'")
{:ok, tree} = Atree.insert(tree, "premium", "subscription == 'premium'")
{:ok, tree} = Atree.insert(tree, "free", "subscription == 'free'")

user = %{"role" => "manager", "subscription" => "premium"}

{:ok, perms} = Atree.match(tree, user)
# => {:ok, ["manager", "premium"]}
```

## Troubleshooting

### Missing Erlang headers

```bash
# Find Erlang root
erl -eval 'io:format("~s~n", [code:root_dir()])' -s init stop -noshell
# Should output something like: /usr/lib/erlang

# Verify headers exist
ls /usr/lib/erlang/usr/include/erl_nif.h
```

### Compilation fails

1. Check C++ compiler supports C++17:
   ```bash
   g++ -std=c++17 -dM -E - </dev/null | grep __cplusplus
   ```
   Should show: `#define __cplusplus 201703L` or higher

2. Clean and rebuild:
   ```bash
   mix clean
   mix compile
   ```

3. Check for permission issues:
   ```bash
   ls -la priv/
   # atree_nif.so should exist with execute permissions
   ```

### Runtime NIF loading error

If you get `UndefinedFunctionError: function Atree.new/0 is undefined`

1. NIF library didn't load - check compilation
2. Try clean rebuild:
   ```bash
   mix clean
   rm -rf _build priv/
   mix compile
   ```

## Next Steps

1. **Read Documentation**:
   - [README.md](README.md) - Feature overview
   - [ARCHITECTURE.md](ARCHITECTURE.md) - Design details

2. **Explore Examples**:
   - See [src/atree_nif_examples.ex](src/atree_nif_examples.ex)

3. **Review Tests**:
   - See [test/atree_nif_test.exs](test/atree_nif_test.exs)

4. **Extend the Project**:
   - Add custom rule functions
   - Implement rule optimization
   - Add persistence/serialization
   - Create rule builders

## Common Operations

### Insert Multiple Rules

```elixir
rules = %{
  "rule1" => "age > 30",
  "rule2" => "status == 'active'",
  "rule3" => "balance > 1000"
}

tree =
  Enum.reduce(rules, tree, fn {item_id, rule}, acc ->
    {:ok, updated} = Atree.insert(acc, item_id, rule)
    updated
  end)
```

### Batch Matching

```elixir
values_list = [
  %{"age" => 25},
  %{"age" => 35},
  %{"age" => 45}
]

results = Enum.map(values_list, fn values ->
  {:ok, matches} = Atree.match(tree, values)
  {values, matches}
end)
```

### Performance Testing

```elixir
{time, result} = :timer.tc(fn ->
  Atree.match(tree, %{"age" => 40, "status" => "active"})
end)

IO.puts("Query took #{time}μs")
IO.puts("Found #{length(elem(result, 1))} matches")
```

## Getting Help

1. Check module documentation:
   ```elixir
   iex> h Atree
   ```

2. Check specific function:
   ```elixir
   iex> h Atree.match
   ```

3. View examples:
   ```elixir
   iex> Atree.Examples.simple_example()
   ```

4. Review code:
   - Elixir: [src/atree_nif.ex](src/atree_nif.ex)
   - C++: [c_src/atree_nif.cpp](c_src/atree_nif.cpp)
   - Header: [c_src/atree.h](c_src/atree.h)

## Commands Reference

```bash
# Build
mix compile          # Compile both C++ and Elixir
mix clean            # Clean all build artifacts

# Test
mix test             # Run tests
mix test --cover     # Run with coverage

# Documentation
mix docs             # Generate HTML docs (requires ex_doc)

# IEx
iex -S mix          # Interactive shell with compiled code

# Utilities
mix format          # Format code
mix credo           # Lint code (if installed)
```

# Atree

[![build](https://github.com/saleyn/exatree-rules/actions/workflows/ci.yml/badge.svg)](https://github.com/saleyn/exatree-rules/actions/workflows/build.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/exatree-rules.svg)](https://hex.pm/packages/exatree-rules)
[![Hex.pm](https://img.shields.io/hexpm/dt/exatree-rules.svg)](https://hex.pm/packages/exatree-rules)

Rule-based matching engine for Elixir using C++ NIFs. Store opaque items with 
associated boolean expression rules, then match incoming value maps against all 
rules to find matching items.

## Features

- **Rule-Based Matching**: Associate opaque items with compiled boolean expression rules
- **Rich Expression Language**: Support for arithmetic, logical, and list operations
- **High Performance**: Built in C++ for performance-critical matching operations
- **Flexible Value Matching**: Match against maps with numbers, strings, and booleans
- **Thread-Safe**: Safe to use in concurrent Elixir applications

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:atree_nif, path: "path/to/atree-nif"}
  ]
end
```

## Quick Start

```elixir
# Create a new rule tree
{:ok, tree} = Atree.new()

# Insert items with rules
{:ok, tree} = Atree.insert(tree, "rule1", "age > 30 and status == 'active'")
{:ok, tree} = Atree.insert(tree, "rule2", "tv_brand in ['Samsung', 'LG']")
{:ok, tree} = Atree.insert(tree, "rule3", "not premium or age < 18")

# Match a value map against all rules
values = %{
  "age" => 40,
  "status" => "active",
  "tv_brand" => "Samsung",
  "premium" => false
}

{:ok, matched} = Atree.match(tree, values)
# => {:ok, ["rule1", "rule2"]}
```

## Rule Syntax

Rules are boolean expressions with the following operators:

### Comparison Operators
- `>` - Greater than: `age > 30`
- `<` - Less than: `age < 25`
- `>=` - Greater than or equal: `age >= 18`
- `<=` - Less than or equal: `age <= 65`
- `==` - Equal: `status == 'active'`
- `!=` - Not equal: `status != 'deleted'`

### Logical Operators
- `and` - Both conditions true: `age > 30 and status == 'active'`
- `or` - At least one true: `status == 'vip' or balance > 5000`
- `not` - Negation: `not suspended`

### Membership
- `in` - Check membership: `brand in ['Apple', 'Samsung', 'LG']`

### Values
- Numbers: `42`, `3.14` (integers and floats)
- Strings: `'text'` or `"text"` (single or double quoted)
- Booleans: `true`, `false`
- Variables: Any identifier (matched from value map)

### Grouping
- Parentheses: `(age > 30 and age < 65)`

## API Reference

### Tree Management

- `new() :: {:ok, reference}`
  - Create a new empty rule tree

- `clear(tree) :: :ok`
  - Clear all items from the tree

- `empty(tree) :: {:ok, boolean}`
  - Check if tree is empty

- `count(tree) :: {:ok, non_neg_integer}`
  - Get the number of items in the tree

### Item Operations

- `insert(tree, item_id, rule) :: {:ok, tree} | {:error, :item_exists}`
  - Insert an item with a rule
  - `item_id`: String identifier (must be unique)
  - `rule`: Boolean expression rule string
  - Returns error if item_id already exists

- `remove(tree, item_id) :: {:ok, tree} | {:error, :not_found}`
  - Remove an item from the tree
  - Returns error if item not found

- `exists(tree, item_id) :: {:ok, boolean}`
  - Check if an item exists in the tree

### Matching

- `match(tree, value_map) :: {:ok, [item_id]} | {:error, :invalid_map}`
  - Match a value map against all rules
  - Returns list of matching item IDs
  - `value_map`: Map with string keys and numeric/string/boolean values

### Introspection

- `all_items(tree) :: {:ok, [item_id]}`
  - Get all item IDs in the tree

## Examples

### User Segmentation

```elixir
{:ok, tree} = Atree.new()

# Define user segments
{:ok, tree} = Atree.insert(tree, "vip", "lifetime_spend > 10000 and account_age > 365")
{:ok, tree} = Atree.insert(tree, "engaged", "login_count > 50 and days_since_login < 7")
{:ok, tree} = Atree.insert(tree, "churned", "days_since_login > 90")
{:ok, tree} = Atree.insert(tree, "trial", "account_age <= 30 and status == 'trial'")

# Check which segments a user belongs to
user = %{
  "lifetime_spend" => 15000,
  "account_age" => 500,
  "login_count" => 150,
  "days_since_login" => 2,
  "status" => "active"
}

{:ok, segments} = Atree.match(tree, user)
# => {:ok, ["vip", "engaged"]}
```

### Product Filtering

```elixir
{:ok, tree} = Atree.new()

{:ok, tree} = Atree.insert(tree, "must_reorder", "stock < 10")
{:ok, tree} = Atree.insert(tree, "on_sale", "discount > 0")
{:ok, tree} = Atree.insert(tree, "low_margin", "margin < 10")

product = %{"stock" => 5, "discount" => 25, "margin" => 8}

{:ok, actions} = Atree.match(tree, product)
# => {:ok, ["must_reorder", "on_sale", "low_margin"]}
```

## Performance Characteristics

### Time Complexity

- **Insert**: O(p) where p is rule parsing overhead (typically 100μs-1ms)
- **Match**: O(n * c) where n is number of items, c is average evaluation cost

### Optimization Tips

1. **Use simpler rules** - Complex nested expressions take longer to evaluate
2. **Order rules efficiently** - Most frequently true rules should be inserted first (NIF evaluation is sequential)
3. **Index by partial values** - Use multiple lower-cost rules instead of one expensive rule
4. **Batch matches** - Reuse the tree for multiple value maps

## Building

### Requirements

- Erlang/OTP development headers
- C++ compiler (g++ ≥ 7.0 or clang++ ≥ 5.0)
- Make
- Elixir 1.14+

### Build Steps

```bash
# Compile NIF and Elixir code
mix compile

# Run tests
mix test

# Build documentation
mix docs
```

## Architecture

### Expression Engine

The C++ expression engine supports:
- **Tokenization**: Converts rule strings into tokens
- **Parsing**: Builds an Abstract Syntax Tree (AST)
- **Evaluation**: Evaluates AST against value maps

### Rule Tree

Stores items with compiled expression trees for efficient matching.

### NIF Wrapper

Safely marshals data between Erlang/Elixir and C++ implementation.

## Testing

```bash
# Run all tests
mix test

# Run specific test file
mix test test/atree_nif_test.exs

# Run with coverage
mix test --cover
```

## Examples

Run examples in IEx:

```bash
iex -S mix
```

Then:

```elixir
# Simple example
Atree.Examples.simple_example()

# Inventory filtering
Atree.Examples.inventory_filtering_example()

# User segmentation
Atree.Examples.user_segmentation_example()

# Benchmark
Atree.Examples.benchmark_example()

# Operator reference
Atree.Examples.operators_example()
```

## License

MIT License - See [LICENSE](./LICENSE) file for details

## Contributing

Contributions are welcome! Please ensure:
- All tests pass
- Code follows the style guide
- Documentation is updated
- New features include tests


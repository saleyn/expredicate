# Expredicate

[![build](https://github.com/saleyn/expredicate/actions/workflows/build.yml/badge.svg)](https://github.com/saleyn/expredicate/actions/workflows/build.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/expredicate.svg)](https://hex.pm/packages/expredicate)
[![Hex.pm](https://img.shields.io/hexpm/dt/expredicate.svg)](https://hex.pm/packages/expredicate)

High-performance predicate matching engine for Elixir using C++ NIFs. Store opaque items with 
associated boolean expression rules, then match incoming value maps against all 
rules to find matching items.

## Features

- **Predicate-Based Matching**: Associate opaque items with compiled boolean expression predicates
- **Rich Expression Language**: Support for arithmetic, logical, and list operations
- **High Performance**: Built in C++ for performance-critical matching operations
- **Flexible Value Matching**: Match against maps with numbers, strings, and booleans
- **Thread-Safe**: Safe to use in concurrent Elixir applications

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:expredicate, github: "saleyn/expredicate"}
  ]
end
```

## Quick Start

```elixir
# Create a new rule tree
tree = Expredicate.new()

# Insert items with rules
{:ok, tree} = Expredicate.insert(tree, "rule1", "age > 30 and status == 'active'")
{:ok, tree} = Expredicate.insert(tree, "rule2", "tv_brand any in ['Samsung', 'LG']")
{:ok, tree} = Expredicate.insert(tree, "rule3", "not premium or age < 18")

# Match a value map against all rules
# Variables can be scalars or lists
values = %{
  "age" => 40,
  "status" => "active",
  "tv_brand" => ["Samsung", "Sony"],  # List variable
  "premium" => false
}

matched = Expredicate.match(tree, values)
# => ["rule1", "rule2"] (rule2 matches: "Samsung" is in ['Samsung', 'LG'])
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

### List Membership
- `in [...]` / `all in [...]` - All list items in RHS list: `id in ['A1', 'A2']` or `tags all in ['important', 'urgent']`
- `not in [...]` / `all not in [...]` - All list items not in RHS list: `status not in ['deleted', 'archived']`
- `any in [...]` - Any list item in RHS list: `tags any in ['vip', 'important']`
- `any not in [...]` - Any list item not in RHS list: `blocked_codes any not in ['TEMP', 'REVIEW']`

### Values
- Numbers: `42`, `3.14` (integers and floats)
- Strings: `'text'` or `"text"` (single or double quoted)
- Strings (from variables): Can be lists where each element is tested
- Booleans: `true`, `false`
- Variables: Any identifier (matched from value map, can be scalar or list)

### Grouping
- Parentheses: `(age > 30 and age < 65)`

## API Reference

### Tree Management

- `new() :: reference`
  - Create a new empty rule tree
  - Optional parameters:
    - `:engine` - `:parser` (default) or `:bytecode`
    - `:nocase` - `true` for case-insensitive string comparisons, `false` (default)
  - Example: `new(engine: :bytecode, nocase: true)` - use bytecode engine with case-insensitive matching

- `clear(tree) :: :ok`
  - Clear all items from the tree

- `empty(tree) :: boolean`
  - Check if tree is empty

- `count(tree) :: non_neg_integer`
  - Get the number of items in the tree

### Item Operations

- `insert(tree, item, rule) :: {:ok, reference()} | {:error, :item_exists}`
  - Insert an item with a rule
  - `item`: String identifier or tuple `{item_id, metadata}` (must be unique)
  - `rule`: Boolean expression rule string
  - Returns error if item already exists

- `remove(tree, item_id) :: {:ok, reference()} | {:error, :not_found}`
  - Remove an item from the tree
  - Returns error if item not found

- `exists(tree, item_id) :: boolean`
  - Check if an item exists in the tree

### Matching

- `match(tree, value_map) :: [item_id]`
  - Match a value map against all rules
  - Returns list of matching item IDs
  - `value_map`: Map with string keys and numeric/string/boolean values
  - Optional: `match(tree, value_map, options)` with options map (e.g., `result: :metadata`)

### Introspection

- `all_items(tree) :: [item_id]`
  - Get all item IDs in the tree

## Examples

### User Segmentation

```elixir
tree = Expredicate.new()

# Define user segments
Expredicate.insert!(tree, "vip", "lifetime_spend > 10000 and account_age > 365")
Expredicate.insert!(tree, "engaged", "login_count > 50 and days_since_login < 7")
Expredicate.insert!(tree, "churned", "days_since_login > 90")
Expredicate.insert!(tree, "trial", "account_age <= 30 and status == 'trial'")

# Check which segments a user belongs to
user = %{
  "lifetime_spend" => 15000,
  "account_age" => 500,
  "login_count" => 150,
  "days_since_login" => 2,
  "status" => "active"
}

segments = Expredicate.match(tree, user)
# => ["vip", "engaged"]
```

### Product Filtering

```elixir
tree = Expredicate.new()

{:ok, tree} = Expredicate.insert(tree, "must_reorder", "stock < 10")
{:ok, tree} = Expredicate.insert(tree, "on_sale",      "discount > 0")
{:ok, tree} = Expredicate.insert(tree, "low_margin",   "margin < 10")
{:ok, tree} = Expredicate.insert(tree, "restricted",   "certifications not in ['FDA', 'CE']")

product = %{"stock" => 5, "discount" => 25, "margin" => 8, "certifications" => ["UL"]}

actions = Expredicate.match(tree, product)
# => ["must_reorder", "on_sale", "low_margin", "restricted"]
```

### Tag-Based Rules with List Values

```elixir
tree = Expredicate.new()

# Rules for items with multiple tags
{:ok, tree} = Expredicate.insert(tree, "urgent", "tags any in ['URGENT', 'CRITICAL']")
{:ok, tree} = Expredicate.insert(tree, "safe", "tags all in ['APPROVED', 'TESTED']")
{:ok, tree} = Expredicate.insert(tree, "blocked", "tags any in ['BLOCKED', 'HOLD']")

# Match items - variables can contain lists
item = %{"tags" => ["REVIEWED", "URGENT", "DRAFT"]}

actions = Expredicate.match(tree, item)
# => ["urgent"] (has URGENT, but not all tags in ['APPROVED', 'TESTED'])
```

### Case-Insensitive Matching

```elixir
# With nocase: true, all string comparisons are case-insensitive
tree = Expredicate.new(nocase: true)

{:ok, tree} = Expredicate.insert(tree, "premium", "status == 'Premium'")
{:ok, tree} = Expredicate.insert(tree, "restricted", "country not in ['USA', 'Canada']")

# Rules match regardless of case
values = %{
  "status" => "premium",  # lowercase matches 'Premium'
  "country" => "uk"
}

matched = Expredicate.match(tree, values)
# => ["premium", "restricted"]
# - "premium" matches because 'premium' == 'Premium' (case-insensitive)
# - "restricted" matches because "uk" not in ['USA', 'Canada'] (case-insensitive)
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
Expredicate.Examples.simple_example()

# Inventory filtering
Expredicate.Examples.inventory_filtering_example()

# User segmentation
Expredicate.Examples.user_segmentation_example()

# Benchmark
Expredicate.Examples.benchmark_example()

# Operator reference
Expredicate.Examples.operators_example()
```

## License

MIT License - See [LICENSE](./LICENSE) file for details

## Contributing

Contributions are welcome! Please ensure:
- All tests pass
- Code follows the style guide
- Documentation is updated
- New features include tests


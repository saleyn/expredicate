# Architecture Documentation

## Overview

Atree is a rule-based matching engine that stores opaque items with associated boolean expression rules, then evaluates incoming value maps against those rules to find matches. Built as a hybrid Elixir/C++ project using NIFs for performance.

## Directory Structure

```
atree-nif/
├── c_src/                    # C++ source code
│   ├── atree.h              # Expression engine and rule tree
│   ├── atree_nif.cpp        # NIF wrapper layer
│   └── Makefile             # Build configuration
├── src/                      # Elixir source code
│   ├── atree_nif.ex         # Main module
│   └── atree_nif_examples.ex # Usage examples
├── test/                     # Test suite
│   ├── atree_nif_test.exs
│   └── test_helper.exs
├── config/                   # Configuration
│   └── config.exs
├── priv/                     # Compiled NIF library (generated)
│   └── atree_nif.so
├── mix.exs                   # Elixir project config
├── rebar.config             # Erlang build config
└── README.md                # Documentation
```

## Technology Stack

- **Language**: Elixir 1.14+ with C++17
- **Build System**: Mix + Rebar3 + Make
- **NIF API**: Erlang/OTP NIF (C interface)
- **Dependencies**: None for runtime, standard Erlang/Elixir headers

## Core Components

### 1. Expression System (C++)

#### Tokenizer
Converts rule strings into tokens:
- Handles string literals with quotes
- Recognizes operators: `()[]<>!=,`
- Preserves identifiers and numbers

#### Parser
Builds an Abstract Syntax Tree (AST) with operator precedence:
- **Level 1 (lowest)**: OR - `or`
- **Level 2**: AND - `and`
- **Level 3**: NOT - `not`
- **Level 4**: Comparison - `<`, `>`, `<=`, `>=`, `==`, `!=`, `in`
- **Level 5 (highest)**: Primary - literals, identifiers, parentheses

```
Expression Tree Example:
"age > 30 and status == 'active'"

         AND
        /   \
       >     ==
      / \    / \
    age  30 status 'active'
```

#### Evaluator
Evaluates AST against a value map:
- Resolves identifiers from the value map
- Applies operations based on AST nodes
- Supports type coercion (number/string/boolean)

### 2. Value System

```cpp
using Value = std::variant<bool, double, std::string>;
using ValueMap = std::unordered_map<std::string, Value>;
```

**Supported Types**:
- Numbers: All numeric literals converted to `double`
- Strings: Quoted text ('abc' or "abc")
- Booleans: `true` / `false`

### 3. Expression AST

```cpp
struct Expression {
    enum class Type {
        LITERAL_BOOL,        // true, false
        LITERAL_NUMBER,      // 42, 3.14
        LITERAL_STRING,      // 'text'
        IDENTIFIER,          // age, status (from value map)
        BINARY_OP,          // +, -, *, >, <, ==, !=, and, or
        UNARY_OP,           // not
        IN_LIST,            // in [...]
    };
    
    Type type;
    Value value;           // For literals
    std::string op;        // For operators
    std::vector<std::string> list_items;  // For IN
    std::shared_ptr<Expression> left;
    std::shared_ptr<Expression> right;
};
```

### 4. RuleTree Data Structure

```cpp
class RuleTree {
private:
    std::unordered_map<std::string, std::shared_ptr<Expression>> rules;
    // item_id -> compiled expression tree
};
```

**Operations**:
- `insert(item_id, rule)` - O(p) where p = parse time
- `match(values)` - O(n × c) where n = items, c = eval cost
- `remove(item_id)` - O(1)
- `count()` - O(1)

## NIF Wrapper Architecture

### Layers

```
┌─────────────────────────────┐
│    Elixir Application       │
│    (Atree module)        │
└──────────────┬──────────────┘
               │ NIF calls
┌──────────────▼──────────────┐
│   Erlang NIF Interface      │
│  (atree_nif.cpp)            │
├─────────────────────────────┤
│  - Function dispatch        │
│  - Term marshaling          │
│  - Resource management      │
│  - Type conversion          │
└──────────────┬──────────────┘
               │ C++ calls
┌──────────────▼──────────────┐
│   Expression Engine         │
│   & Rule Matching           │
│   (atree.h / C++)           │
├─────────────────────────────┤
│  - Tokenizer                │
│  - Parser                   │
│  - Evaluator                │
│  - RuleTree                 │
└─────────────────────────────┘
```

### Resource Management

The C++ `RuleTree` object is wrapped in an Erlang resource:
- Created by `nif_new()`: allocates resource with custom destructor
- Referenced in Elixir as an opaque `reference()`
- Automatically cleaned up when Erlang GC collects the reference

### Term Marshaling

**Input Handling**:
- Item ID: Erlang binary string → C++ std::string
- Rule: Erlang binary string → C++ std::string
- Value Map: Erlang map → C++ unordered_map<string, Value>

**Output Handling**:
- Error atoms: {:error, :atom}
- Match results: {:ok, [item_id_list]}
- Status: {:ok, true/false}

**Type Conversion** (Erlang values to C++):
```
ERL_NIF_TERM → Value
  Integers/Floats → double
  Strings/Binaries → std::string
  Atoms (true/false) → bool
```

## Expression Evaluation Flow

```
1. User calls: match(tree, %{"age" => 40, "status" => "active"})
                                    ↓
2. Erlang NIF: erlang_map_to_valuemap() converts to C++ map
                                    ↓
3. For each item in tree:
   - Get compiled rule expression
   - Call ExpressionEngine::evaluate(expression, values)
                                    ↓
4. Evaluation process:
   - Traverse AST depth-first
   - For IDENTIFIER nodes: look up in values map
   - For BINARY_OP: apply operation to left/right results
   - For IN_LIST: check membership in list
                                    ↓
5. Return true/false for each item
                                    ↓
6. Collect matching item IDs into list
                                    ↓
7. Return to Elixir: {:ok, [matched_ids]}
```

## Build Process

### Compilation Flow

1. **Mix compilation**:
   ```bash
   mix compile
   ```
   - Triggers rebar.config pre_hooks
   - Calls `make -C c_src`

2. **Make compilation**:
   ```bash
   make -C c_src
   ```
   - Compiles atree_nif.cpp with C++17
   - Includes Erlang headers from ERL_ROOT
   - Links as shared library (.so)
   - Output: `priv/atree_nif.so`

3. **NIF Loading** (at application start):
   - Loads `priv/atree_nif.so`
   - Registers NIF functions (9 total)
   - Initializes resource type

### Compiler Flags

```
CXXFLAGS = -O2 -std=c++17 -fPIC -Wall -Wextra
CPPFLAGS = -I$(ERL_INCLUDE)
```

## API Surface

### NIF Functions (9 total)

| Function | Args | Returns | Description |
|----------|------|---------|---|
| `new` | 0 | `{ok, ref}` | Creates new tree |
| `insert` | 3 | `{ok, ref} \| {error, :item_exists}` | Adds item+rule |
| `remove` | 2 | `{ok, ref} \| {error, :not_found}` | Removes item |
| `match` | 2 | `{ok, [items]} \| {error, :invalid_map}` | Match values |
| `all_items` | 1 | `{ok, [items]}` | Get all items |
| `count` | 1 | `{ok, count}` | Item count |
| `clear` | 1 | `:ok` | Clear tree |
| `empty` | 1 | `{ok, bool}` | Check if empty |
| `exists` | 2 | `{ok, bool}` | Check item exists |

### Elixir API

Functions in `Atree` module wrap corresponding NIFs with documentation and type hints.

## Performance Characteristics

### Time Complexity

- **Insert**: O(p) - p = rule parsing/compilation time (100μs-1ms)
- **Match**: O(n × c) - n = number of items, c = avg evaluation cost (~10-100μs per rule)
- **Remove**: O(1) - simple map lookup and delete
- **Count/Empty/Exists**: O(1)

### Space Complexity

- O(s + n × a) where:
  - s = total rule string storage
  - n = number of items
  - a = average AST size (typically 20-50 bytes per rule)

### Memory Overhead per Rule

- Item ID: ~variable (string length)
- AST storage: ~20-50 bytes per expression node
- Example: 50-byte rule ≈ 50-100 bytes total

## Error Handling

### Parse Errors

When rule parsing fails:
- `insert()` returns `{:error, :item_exists}` (item not added)
- Invalid syntax is caught during parse phase

### Evaluation Errors

During matching:
- Missing variables default to `false`
- Type mismatches are handled gracefully
- Evaluation errors skip the item (doesn't match)

### NIF Errors

- Invalid resource: returns `badarg`
- Invalid value map: returns `{:error, :invalid_map}`
- Memory allocation failure: propagates OS error

## Thread Safety

### Guarantees

- **Per-tree**: NOT thread-safe (single writer expected)
- **Across trees**: Multiple trees can be used concurrently
- **NIF calls**: Properly handle Erlang scheduler

### Safe Usage Pattern

```elixir
# Safe - different processes, different trees
Task.start(fn -> 
  {:ok, tree1} = Atree.new()
  # ... use tree1
end)

Task.start(fn -> 
  {:ok, tree2} = Atree.new()
  # ... use tree2
end)

# Unsafe - same tree, concurrent modifications
Task.start(fn -> Atree.insert(shared_tree, "a", "rule") end)
Task.start(fn -> Atree.insert(shared_tree, "b", "rule") end)
```

## Operator Precedence

From lowest to highest binding strength:

| Level | Operators | Associativity |
|-------|-----------|---|
| 1 | `or` | Left |
| 2 | `and` | Left |
| 3 | `not` | Right |
| 4 | `<`, `>`, `<=`, `>=`, `==`, `!=`, `in` | Left |
| 5 | Literals, identifiers, `()` | N/A |

## Example: Rule Evaluation

```
Rule: "age > 30 and status == 'active'"
Values: {"age" => 35, "status" => "active"}

Parse:
  AND(>(age, 30), ==(status, 'active'))

Evaluate:
  1. Evaluate >(age, 30):
     - Look up "age" in values → 35
     - Look up 30 → 30
     - Compare: 35 > 30 → true
     
  2. Evaluate ==(status, 'active'):
     - Look up "status" in values → "active"
     - Look up 'active' → "active"
     - Compare: "active" == "active" → true
     
  3. Combine with AND:
     - true AND true → true

Result: Item MATCHES
```

## Future Enhancements

Possible improvements:
- Binary pattern support (not just strings)
- Rule optimization/indexing for faster matching
- Fuzzy matching and similarity scoring
- Rule serialization/persistence
- Regex pattern support
- Type system (optional strict typing)
- Rule compilation caching
- Query optimization (reorder expressions)

## References

- [Erlang NIF API](https://www.erlang.org/doc/man/erl_nif.html)
- [C++17 Standard](https://en.cppreference.com/w/cpp/17)
- [Elixir NIF Guide](https://hexdocs.pm/elixir/main/NIF.html)
- [Expression Parsing Techniques](https://en.wikipedia.org/wiki/Recursive_descent_parser)

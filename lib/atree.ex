defmodule Atree do
  @moduledoc """
  Rule-based matching engine via NIF.

  Store opaque items with associated boolean expression rules. Match incoming
  value maps against all rules to find matching items.

  Rules are compiled boolean expressions supporting:
  - Comparison operators: `>`, `<`, `>=`, `<=`, `==`, `!=`
  - Logical operators: `and`, `or`, `not`
  - List membership: `in ['value1', 'value2']`, `not in ['value1', 'value2']`
  - Values: numbers, strings, booleans
  - Variables: referenced from the value map

  ## Examples

      iex> tree = Atree.new()
      iex> tree = Atree.insert!(tree, "rule1", "age > 30 and status == 'active'")
      iex> tree = Atree.insert!(tree, "rule2", "tv_brand in ['Samsung', 'LG']")
      iex> tree = Atree.insert!(tree, "rule3", "tv_brand not in ['Samsung', 'LG']")
      iex> items = Atree.all_items(tree)
      iex> Enum.sort(items)
      ["rule1", "rule2", "rule3"]

  """

  @on_load  :load_nifs
  # Suppress type checking warnings for NIF stub functions
  # These implementations are replaced by the NIF at runtime
  @dialyzer {:nowarn_function,
             [
               {:new,       0},
               {:new,       1},
               {:insert,    3},
               {:insert!,   3},
               {:remove,    2},
               {:match,     2},
               {:match,     3},
               {:all_items, 1},
               {:count,     1},
               {:clear,     1},
               {:empty,     1},
               {:exists,    2}
             ]}

  def load_nifs do
    nif_path = :filename.join(:code.priv_dir(:exatree), ~c"atree")
    :erlang.load_nif(nif_path, 0)
  end

  @doc """
  Create a new rule tree with optional engine selection.

  Create a new empty rule tree. Optionally specify which expression engine to use
  and whether to use case-insensitive string comparisons.

  ## Parameters

  - `options`: Optional keyword list or map controlling behavior:
    - `:engine` - `:parser` (default) or `:bytecode`
    - `:nocase` - `true` for case-insensitive string comparisons, `false` (default) for case-sensitive

  ## Engine Selection

  - **`:parser`** (default): Custom recursive descent parser
    - Better for typical workloads (insert, then evaluate once per query)
    - Simpler implementation, easier to maintain
    - ~1.24 μs evaluation time per rule

  - **`:bytecode`**: Stack-based virtual machine
    - Better for high-volume streaming workloads
    - Evaluates pre-compiled bytecode (23% faster than parser)
    - Use when: insert rules once, evaluate millions of times
    - ~0.95 μs evaluation time per rule

  ## Case Sensitivity

  When `:nocase` is `true`, all string comparisons are case-insensitive:
  - `status == 'Active'` will match `status == 'active'` or `status == 'ACTIVE'`
  - `brand in ['Samsung', 'LG']` will match `'samsung'` or `'lg'`
  - String comparison operators: `==`, `!=`, list membership (`in`, `not in`, `any in`, `any not in`)

  Does **not** affect:
  - Variable names (identifiers): still case-sensitive
  - Operator keywords: still case-sensitive
  - Numeric and boolean values: not affected

  ## Examples

      iex> tree = Atree.new()
      iex> is_reference(tree)
      true

  With engine selection:

      iex> tree = Atree.new(engine: :bytecode)
      iex> is_reference(tree)
      true

  With case-insensitive matching:

      iex> tree = Atree.new(nocase: true)
      iex> is_reference(tree)
      true

  With multiple options:

      iex> tree = Atree.new(engine: :bytecode, nocase: true)
      iex> is_reference(tree)
      true

  With map options:

      iex> tree = Atree.new(%{engine: :bytecode, nocase: true})
      iex> is_reference(tree)
      true

  """
  @spec new() :: reference()
  @spec new(keyword() | map()) :: reference()
  def new(), do: new(%{})

  def new(options) when is_list(options) do
    new(Map.new(options))
  end

  def new(_options) do
    :erlang.nif_error("NIF not loaded")
  end

  @doc """
  Insert an item with a rule into the tree.

  Returns `{:ok, tree}` on successful insertion, or `{:error, :item_exists}`
  if the item ID already exists.

  ## Parameters

  - `tree`: A rule tree reference
  - `item`: Either a string item ID or a tuple `{item_id, metadata}` to store metadata
  - `rule`: Boolean expression rule string

  ## Supported Rule Syntax

  - Operators: `>`, `<`, `>=`, `<=`, `==`, `!=`, `and`, `or`, `not`
  - List membership: `field in ['value1', 'value2']`
  - Literals: numbers (42, 3.14), strings ('text', "text"), booleans (true, false)
  - Variables: Any identifier not quoted (matched from value map)
  - Grouping: `(expr)`

  ## Rule Examples

      - `"age > 30"`
      - `"status == 'active' and age <= 65"`
      - `"tv_brand in ['Samsung', 'LG']"`
      - `"tv_brand not in ['Samsung', 'LG']"`
      - `"not premium or age < 18"`
      - `"tags any in ['new', 'sale', 'special']"`

  ## Examples

      iex> tree = Atree.new()
      iex> {:ok, tree} = Atree.insert(tree, "item1", "age > 30")
      iex> {:error, :item_exists} = Atree.insert(tree, "item1", "age < 50")
      {:error, :item_exists}

  With metadata:

  ```
  Atree.insert(tree, {"user_rule", %{"category" => "adult"}}, "age > 30")
  ```

  """
  @spec insert(reference(), String.t() | {String.t(), any()}, String.t()) ::
          {:ok, reference()} | {:error, :item_exists}
  def insert(_tree, item, rule) when (is_binary(item) or is_tuple(item)) and is_binary(rule) do
    :erlang.nif_error("NIF not loaded")
  end

  @doc """
  Insert an item with a rule into the tree, raising on error.

  Returns the tree on successful insertion, or raises `ArgumentError`
  if the item ID already exists.

  ## Examples

      iex> tree = Atree.new()
      iex> tree = Atree.insert!(tree, "item1", "age > 30")
      iex> is_reference(tree)
      true

  """
  @spec insert!(reference(), String.t() | {String.t(), any()}, String.t()) :: reference()
  def insert!(tree, item, rule) do
    case insert(tree, item, rule) do
      {:ok,    updated_tree} -> updated_tree
      {:error, reason}       -> raise ArgumentError, "insert! failed: #{inspect(reason)}"
    end
  end

  @doc """
  Remove an item from the tree.

  Returns `{:ok, tree}` if the item was found and removed, or
  `{:error, :not_found}` if the item does not exist.

  ## Examples

      iex> tree = Atree.new()
      iex> Atree.insert!(tree, "item1", "age > 30") |> Atree.exists("item1")
      true
      iex> Atree.remove!(tree, "item1") |> Atree.exists("item1")
      false
      iex> {:error, :not_found} = Atree.remove(tree, "nonexistent")
      {:error, :not_found}

  """
  @spec remove(reference(), String.t()) :: {:ok, reference()} | {:error, :not_found}
  def remove(_tree, item_id) when is_binary(item_id) do
    :erlang.nif_error("NIF not loaded")
  end

  @doc """
  Remove an item from the tree, raising on error.

  Returns the tree on successful removal, or raises `ArgumentError`
  if the item ID does not exist.

  ## Examples

      iex> tree = Atree.new()
      iex> Atree.insert!(tree, "item1", "age > 30") |> Atree.exists("item1")
      true
      iex> Atree.remove!(tree, "item1") |> Atree.exists("item1")
      false

  """
  def remove!(tree, item_id) do
    case remove(tree, item_id) do
      {:ok,    updated_tree} -> updated_tree
      {:error, reason}       -> raise ArgumentError, "remove! failed: #{inspect(reason)}"
    end
  end

  @doc """
  Match a value map against all rules.

  Evaluates all item rules against the provided value map and returns matching results.

  ## Parameters

  - `tree`: A rule tree reference
  - `value_map`: Map with string keys and values (numbers, strings, or booleans)
  - `options`: Optional map controlling result format:
    - `:result` - `:item` (default), `:metadata`, or `:item_with_metadata`

  ## Value Map Example

      %{
        "age"      => 40,
        "status"   => "active",
        "tv_brand" => "Samsung"
      }

  ## Examples

      iex> tree = Atree.new()
      iex> {:ok, tree} = Atree.insert(tree, "rule1", "age > 30")
      iex> {:ok, tree} = Atree.insert(tree, "rule2", "age < 25")
      iex> Atree.match(tree, %{"age" => 35})
      ["rule1"]

  """
  @spec match(reference(), map(), map()) :: list(String.t() | any() | {String.t(), any()})

  def match(_tree, value_map, _options \\ %{}) when is_map(value_map) do
    :erlang.nif_error("NIF not loaded")
  end

  @doc """
  Get all item IDs in the tree.

  Returns a list of all stored item IDs.

  ## Examples

      iex> tree = Atree.new()
      iex> {:ok, tree} = Atree.insert(tree, "a", "age > 30")
      iex> {:ok, tree} = Atree.insert(tree, "b", "age < 25")
      iex> items = Atree.all_items(tree)
      iex> Enum.sort(items)
      ["a", "b"]

  """
  @spec all_items(reference()) :: list(String.t())
  def all_items(_tree) do
    :erlang.nif_error("NIF not loaded")
  end

  @doc """
  Get the number of items in the tree.

  Returns the number of stored items.

  ## Examples

      iex> tree = Atree.new()
      iex> Atree.count(tree)
      0
      iex> {:ok, tree} = Atree.insert(tree, "a", "true")
      iex> Atree.count(tree)
      1

  """
  @spec count(reference()) :: non_neg_integer()
  def count(_tree) do
    :erlang.nif_error("NIF not loaded")
  end

  @doc """
  Clear all items from the tree.

  Returns `:ok`.

  ## Examples

      iex> tree = Atree.new()
      iex> {:ok, tree} = Atree.insert(tree, "item", "age > 30")
      iex> :ok = Atree.clear(tree)
      iex> Atree.count(tree)
      0

  """
  @spec clear(reference()) :: :ok
  def clear(_tree) do
    :erlang.nif_error("NIF not loaded")
  end

  @doc """
  Check if the tree is empty.

  Returns `true` if the tree has no items, `false` otherwise.

  ## Examples

      iex> tree = Atree.new()
      iex> Atree.empty(tree)
      true
      iex> {:ok, tree} = Atree.insert(tree, "item", "age > 30")
      iex> Atree.empty(tree)
      false

  """
  @spec empty(reference()) :: boolean()
  def empty(_tree) do
    :erlang.nif_error("NIF not loaded")
  end

  @doc """
  Check if an item exists in the tree.

  Returns `true` if the item ID exists, `false` otherwise.

  ## Examples

      iex> tree = Atree.new()
      iex> {:ok, tree} = Atree.insert(tree, "a", "age > 30")
      iex> Atree.exists(tree, "a")
      true
      iex> Atree.exists(tree, "b")
      false

  """
  @spec exists(reference(), String.t()) :: boolean()
  def exists(_tree, item_id) when is_binary(item_id) do
    :erlang.nif_error("NIF not loaded")
  end
end

defmodule Atree.App do
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([], strategy: :one_for_one)
  end
end
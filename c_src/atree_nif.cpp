/**
 * AtreeNIF - Erlang Native Interface for Rule-Based Matching Engine
 *
 * This module provides a C++ bridge to Erlang/Elixir for the Atree rule-based
 * matching engine. It translates Elixir function calls to native C++ operations
 * and marshals data between the Erlang virtual machine and C++ data structures.
 *
 * Architecture:
 * - Uses ExpressionEngineInterface abstraction to support multiple engines
 * - Parser Engine (default): Custom recursive descent parser
 * - Bytecode Engine: Pre-compiled bytecode VM for high-volume evaluation
 * - Runtime engine selection via new/1 with engine: :parser | :bytecode
 *
 * Resource Management:
 * - Each rule tree is managed as an Erlang resource (unique_ptr wrapper)
 * - Automatic cleanup via ERL_NIF resource destructor
 * - Placement new/delete for proper unique_ptr construction in Erlang memory
 *
 * Data Type Conversion:
 * - Erlang atoms <-> C++ booleans (true/false)
 * - Erlang numbers <-> C++ double (integer and float)
 * - Erlang binaries/strings <-> C++ std::string
 * - Erlang maps <-> C++ ValueMap (unordered_map)
 *
 * Error Handling:
 * - Invalid arguments return enif_make_badarg(env)
 * - Rule insertion errors return {error, item_exists}
 * - Removal errors return {error, not_found}
 * - All operations resilient to allocation failures
 */

#include <erl_nif.h>
#include <cstring>
#include <memory>
#include <vector>
#include <map>
#include "atree.h"
#include "atree_engine_wrapper.h"

using namespace atree;

/**
 * ============================================================================
 * RESOURCE MANAGEMENT AND GLOBAL STATE
 * ============================================================================
 */

// Resource type descriptor - manages lifetime of rule tree instances
static ErlNifResourceType* rule_tree_resource_type = nullptr;

/**
 * Static atom variables for return values
 * Initialized once in load() to avoid repeated allocation
 * Caching atoms improves performance by avoiding repeated atom lookups
 */
static ERL_NIF_TERM s_am_ok;
static ERL_NIF_TERM s_am_error;
static ERL_NIF_TERM s_am_item_exists;
static ERL_NIF_TERM s_am_not_found;
static ERL_NIF_TERM s_am_true;
static ERL_NIF_TERM s_am_false;
static ERL_NIF_TERM s_am_parser;
static ERL_NIF_TERM s_am_bytecode;
static ERL_NIF_TERM s_am_engine;

/**
 * Resource handle type for unique_ptr wrapper
 * 
 * We store a pointer to unique_ptr in Erlang resource memory because:
 * - Erlang resource system allocates contiguous memory blocks
 * - unique_ptr requires proper construction/destruction
 * - Placement new allows construction in Erlang-allocated memory
 */
using engine_handle = std::unique_ptr<ExpressionEngineInterface>*;

/**
 * Macro: Extract engine handle from Erlang resource
 * 
 * Usage: GET_HANDLE(my_engine, 0)  // Get engine from argv[0]
 * Returns: ExpressionEngineInterface* pointing to the wrapped engine
 * 
 * Safety checks:
 * - Verifies resource is correct type
 * - Validates pointer validity
 * - Returns badarg on any validation failure
 */
#define GET_HANDLE(engine_var, argv_index) \
    engine_handle resource_ptr_mem = nullptr; \
    if (!enif_get_resource(env, argv[argv_index], rule_tree_resource_type, (void**)&resource_ptr_mem)) { \
        return enif_make_badarg(env); \
    } \
    if (!resource_ptr_mem || !*resource_ptr_mem) { \
        return enif_make_badarg(env); \
    } \
    ExpressionEngineInterface* engine_var = resource_ptr_mem->get();

/**
 * ============================================================================
 * RESOURCE LIFECYCLE MANAGEMENT
 * ============================================================================
 */

/**
 * Destructor callback for Erlang resources
 * 
 * Called by Erlang garbage collector when rule_tree resource is freed.
 * Properly destroys the unique_ptr that was created with placement new.
 * 
 * @param env  Erlang environment (unused)
 * @param obj  Pointer to unique_ptr stored in Erlang memory
 */
static void rule_tree_destructor(ErlNifEnv* env, void* obj) {
    (void)env;  // Unused parameter required by NIF interface
    
    // Cast back to unique_ptr pointer and call its destructor
    typedef std::unique_ptr<ExpressionEngineInterface>* engine_ptr_ptr;
    engine_ptr_ptr resource_ptr = static_cast<engine_ptr_ptr>(obj);
    
    if (resource_ptr) {
        try {
            // Call the destructor explicitly (since we used placement new)
            // This properly destroys the contained ExpressionEngineInterface object
            resource_ptr->~unique_ptr();
        } catch (...) {
            // Ignore exceptions during cleanup to prevent crashing Erlang
        }
    }
}

/**
 * ============================================================================
 * DATA TYPE CONVERSION HELPERS
 * ============================================================================
 */

/**
 * Convert Erlang term to C++ Value
 * 
 * Handles multiple Erlang types:
 * - Numbers: integers or floats -> Value(double)
 * - Strings: Latin1 strings -> Value(std::string)
 * - Binaries: binary data -> Value(std::string)
 * - Atoms: :true/:false -> Value(bool)
 * 
 * Conversion process:
 * 1. Try enif_get_double for floating-point numbers
 * 2. Try enif_get_int for 32-bit integers
 * 3. Try enif_get_long for 64-bit integers
 * 4. Try enif_get_string for Latin1 strings
 * 5. Try enif_inspect_binary for arbitrary byte sequences
 * 6. Check atoms for true/false keywords
 * 7. Default to false for unknown types
 * 
 * @param env   Erlang environment pointer
 * @param term  Erlang term to convert
 * @return Value object representing the Erlang term
 */
static Value erlang_to_value(ErlNifEnv* env, ERL_NIF_TERM term) {
    double dv;
    if (enif_get_double(env, term, &dv)) {
        return Value(dv);
    }

    int iv;
    if (enif_get_int(env, term, &iv)) {
        return Value(static_cast<double>(iv));
    }

    long lv;
    if (enif_get_long(env, term, &lv)) {
        return Value(static_cast<double>(lv));
    }

    unsigned len;
    if (enif_get_string_length(env, term, &len, ERL_NIF_LATIN1)) {
        std::string str(len + 1, '\0');
        enif_get_string(env, term, &str[0], len + 1, ERL_NIF_LATIN1);
        return Value(std::string(str.c_str(), len));
    }

    ErlNifBinary bin;
    if (enif_inspect_binary(env, term, &bin)) {
        return Value(std::string(reinterpret_cast<const char*>(bin.data), bin.size));
    }

    // Check for atoms true/false
    if (enif_is_atom(env, term)) {
        char atom_name[256];
        if (enif_get_atom(env, term, atom_name, sizeof(atom_name), ERL_NIF_LATIN1) > 0) {
            if (strcmp(atom_name, "true") == 0) {
                return Value(true);
            }
            if (strcmp(atom_name, "false") == 0) {
                return Value(false);
            }
        }
    }

    return Value(false);
}

/**
 * Convert Erlang map to C++ ValueMap
 * 
 * Iterates through Erlang map entries (key-value pairs) and converts each
 * to C++ std::string (key) and Value (value). Used in rule matching to
 * pass context values to the expression engine.
 * 
 * Map format:
 *   %{key1 => value1, key2 => value2, ...}
 *   Keys must be binaries/strings
 *   Values are converted to Value using erlang_to_value()
 * 
 * Error handling:
 * - Returns false if map_term is not a valid map
 * - Returns false if map iterator creation fails
 * - Returns false if any key is not a binary/string
 * - Destroys iterator on error before returning
 * 
 * @param env         Erlang environment pointer
 * @param map_term    Erlang map term to convert
 * @param result      Output parameter: populated with key-value pairs
 * @return true if conversion succeeded, false otherwise
 */
static bool erlang_map_to_valuemap(ErlNifEnv* env, ERL_NIF_TERM map_term,
                                   ValueMap& result) {
    if (!enif_is_map(env, map_term)) {
        return false;
    }

    ErlNifMapIterator iter;
    if (!enif_map_iterator_create(env, map_term, &iter, ERL_NIF_MAP_ITERATOR_FIRST)) {
        return false;
    }

    ERL_NIF_TERM key, value;
    while (enif_map_iterator_get_pair(env, &iter, &key, &value)) {
        ErlNifBinary key_bin;
        if (enif_inspect_binary(env, key, &key_bin)) {
            std::string key_str((const char*)key_bin.data, key_bin.size);
            result[key_str] = erlang_to_value(env, value);
            enif_map_iterator_next(env, &iter);
        } else {
            enif_map_iterator_destroy(env, &iter);
            return false;
        }
    }

    enif_map_iterator_destroy(env, &iter);
    return true;
}

/**
 * ============================================================================
 * ENGINE INITIALIZATION AND CONFIGURATION
 * ============================================================================
 */

/**
 * Parse engine type from options map
 * 
 * Extracts the 'engine' key from an Elixir map and determines which
 * implementation to use. This allows runtime selection of engine without
 * recompilation.
 * 
 * Options format:
 *   %{}                              -> uses default (PARSER)
 *   %{engine: :parser}               -> uses PARSER engine
 *   %{engine: :bytecode}             -> uses BYTECODE engine
 *   %{other_keys: values}            -> uses default (PARSER)
 * 
 * Engine selection:
 * - PARSER: recursive descent parser, best for dynamic rules
 * - BYTECODE: pre-compiled bytecode VM, best for large rule counts
 * 
 * @param env              Erlang environment pointer
 * @param options_term     Elixir map with optional engine: key
 * @return EngineType enum: PARSER or BYTECODE (default: PARSER)
 */
static EngineType parse_engine_type(ErlNifEnv* env, ERL_NIF_TERM options_term) {
    if (!enif_is_map(env, options_term)) {
        return EngineType::PARSER;  // Default
    }

    ERL_NIF_TERM engine_key = enif_make_atom(env, "engine");
    ERL_NIF_TERM engine_value;

    if (!enif_get_map_value(env, options_term, engine_key, &engine_value)) {
        return EngineType::PARSER;  // Default if key not found
    }

    // Check if engine_value is :bytecode atom
    if (enif_is_identical(engine_value, s_am_bytecode)) {
        return EngineType::BYTECODE;
    }

    // Default to parser
    return EngineType::PARSER;
}

/**
 * ============================================================================
 * ERLANG NIF FUNCTION IMPLEMENTATIONS
 * ============================================================================
 */

/**
 * Create a new rule tree instance
 * 
 * NIF Signature: new/0 | new/1
 * Elixir: Atree.new() | Atree.new(engine: :bytecode)
 * 
 * Creates a new rule tree with an optional engine selection. Each tree is
 * an independent data structure that stores items and their associated rules.
 * Multiple trees can coexist; they don't share state.
 * 
 * Arguments:
 *   argv[0] (optional): Map with engine option
 *                       %{engine: :parser} or %{engine: :bytecode}
 * 
 * Returns:
 *   Erlang resource representing the tree
 *   This resource is automatically garbage collected when no longer referenced
 * 
 * Resource Lifecycle:
 *   1. enif_alloc_resource allocates memory managed by Erlang GC
 *   2. Placement new constructs unique_ptr in that memory
 *   3. enif_make_resource wraps it as an Erlang term
 *   4. enif_release_resource decrements reference count
 *   5. When Erlang GC runs: rule_tree_destructor is called
 *   6. Destructor explicitly calls ~unique_ptr() for cleanup
 * 
 * Error Handling:
 *   - Returns badarg if resource allocation fails
 *   - Returns badarg if engine creation throws exception
 * 
 * Performance Note:
 *   Tree creation is O(1). Memory allocated per tree is ~1KB baseline.
 */
static ERL_NIF_TERM nif_new(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    // Determine which engine to use
    EngineType engine_type = EngineType::PARSER;  // Default

    if (argc > 0 && enif_is_map(env, argv[0])) {
        engine_type = parse_engine_type(env, argv[0]);
    }

    // Allocate Erlang-managed resource memory to hold a unique_ptr
    // We allocate space for the pointer itself, not the unique_ptr object
    using engine_ptr_ptr = std::unique_ptr<ExpressionEngineInterface>*;
    
    engine_ptr_ptr resource_mem = (engine_ptr_ptr)enif_alloc_resource(
        rule_tree_resource_type, sizeof(std::unique_ptr<ExpressionEngineInterface>));
    
    if (!resource_mem)
        return enif_make_badarg(env);
    
    // Use placement new to construct the unique_ptr in the allocated memory
    try {
        new (resource_mem) std::unique_ptr<ExpressionEngineInterface>(
            create_engine(engine_type)
        );
    } catch (...) {
        enif_release_resource(resource_mem);
        return enif_make_badarg(env);
    }

    // Create the Erlang resource term
    ERL_NIF_TERM result = enif_make_resource(env, resource_mem);
    
    // Release the resource - Erlang will call destructor when it's garbage collected
    enif_release_resource(resource_mem);
    
    return result;
}

/**
 * Insert an item with an associated rule
 * 
 * NIF Signature: insert/3
 * Elixir: Atree.insert(tree, item_id, rule_expression)
 * 
 * Adds a new item to the tree with a rule expression. When match/2 is called,
 * this item will be returned if the rule evaluates to true for the provided values.
 * 
 * Arguments:
 *   argv[0]: Tree resource (from Atree.new/0)
 *   argv[1]: Item ID - binary/string uniquely identifying this rule
 *            Can be simple string or {id, metadata} tuple
 *   argv[2]: Rule expression - binary/string with the expression syntax
 *            Format: "field > 10 AND status == 'active'"
 *            Supports: <, >, <=, >=, ==, !=, AND, OR, (, )
 * 
 * Returns:
 *   {:ok, tree}                    if item inserted successfully
 *   {:error, :item_exists}         if item_id already exists in tree
 * 
 * Rule Expression Syntax:
 *   Operators: <, >, <=, >=, ==, !=
 *   Logical:   AND, OR
 *   Precedence: parentheses > AND > OR
 *   Operands: field names (identifiers) and constants
 *   Constants: numbers (123, 45.6) or strings ("hello")
 * 
 * Example:
 *   Atree.insert(tree, "rule_1", "price > 100 AND category == \"electronics\"")
 * 
 * Error Handling:
 *   - Returns badarg if tree or rule are invalid
 *   - Throws item_exists if item_id already exists
 *   - Invalid rule syntax is not checked at insert time;
 *     parsing errors occur during match/2
 * 
 * Performance:
 *   O(rule_expression_length) for parsing
 *   O(1) for storage (assumes hash-based item lookup)
 */
static ERL_NIF_TERM nif_insert(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) {
    GET_HANDLE(engine, 0)

    std::string item_id;

    // Check if argv[1] is a tuple (item_id with metadata) or string (item_id only)
    int arity;
    const ERL_NIF_TERM* tuple_elements;
    if (enif_get_tuple(env, argv[1], &arity, &tuple_elements) && arity == 2) {
        // Tuple case: {item_id, metadata}
        ErlNifBinary item_id_bin;
        if (!enif_inspect_binary(env, tuple_elements[0], &item_id_bin)) {
            return enif_make_badarg(env);
        }
        item_id = std::string((const char*)item_id_bin.data, item_id_bin.size);
    } else {
        // String case: item_id directly
        ErlNifBinary item_id_bin;
        if (!enif_inspect_binary(env, argv[1], &item_id_bin)) {
            return enif_make_badarg(env);
        }
        item_id = std::string((const char*)item_id_bin.data, item_id_bin.size);
    }

    ErlNifBinary rule_bin;
    if (!enif_inspect_binary(env, argv[2], &rule_bin)) {
        return enif_make_badarg(env);
    }
    std::string rule((const char*)rule_bin.data, rule_bin.size);

    bool success = engine->insert(item_id, rule);

    if (success) {
        return enif_make_tuple2(env, s_am_ok, argv[0]);
    } else {
        return enif_make_tuple2(env, s_am_error, s_am_item_exists);
    }
}

/**
 * Remove an item from the tree
 * 
 * NIF Signature: remove/2
 * Elixir: Atree.remove(tree, item_id)
 * 
 * Deletes an item and its associated rule from the tree. Subsequent match/2 calls
 * will no longer return this item, even if its rule would have matched.
 * 
 * Arguments:
 *   argv[0]: Tree resource (from Atree.new/0)
 *   argv[1]: Item ID - binary/string that was previously inserted
 * 
 * Returns:
 *   {:ok, tree}              if item removed successfully
 *   {:error, :not_found}     if item_id not found in tree
 * 
 * Idempotency:
 *   Not idempotent - removing the same item twice returns error on second call
 *   Use exists/2 before remove/2 if you need idempotent behavior
 * 
 * Side Effects:
 *   Frees memory associated with the item's rule
 *   May trigger internal tree rebalancing (engine-dependent)
 * 
 * Error Handling:
 *   - Returns badarg if tree is invalid
 *   - Returns not_found if item_id doesn't exist
 * 
 * Performance:
 *   O(1) average case (hash-based lookup)
 *   May vary by engine implementation
 */
static ERL_NIF_TERM nif_remove(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) {
    GET_HANDLE(engine, 0)

    ErlNifBinary item_id_bin;
    if (!enif_inspect_binary(env, argv[1], &item_id_bin)) {
        return enif_make_badarg(env);
    }
    std::string item_id((const char*)item_id_bin.data, item_id_bin.size);

    bool found = engine->remove(item_id);
    
    if (found) {
        return enif_make_tuple2(env, s_am_ok, argv[0]);
    } else {
        return enif_make_tuple2(env, s_am_error, s_am_not_found);
    }
}

/**
 * Match values against all rules in the tree
 * 
 * NIF Signature: match/2 | match/3
 * Elixir: Atree.match(tree, values) | Atree.match(tree, values, options)
 * 
 * Evaluates all rules in the tree against the provided values and returns
 * a list of item IDs whose rules match (evaluate to true). This is the primary
 * query operation for rule-based filtering.
 * 
 * Arguments:
 *   argv[0]: Tree resource (from Atree.new/0)
 *   argv[1]: Values map %{field1 => value1, field2 => value2, ...}
 *            - Keys must be binary/strings (field names in rules)
 *            - Values can be numbers, strings, or atoms (converted to Value)
 *            - Missing fields are treated as undefined in expressions
 *   argv[2] (optional): Options map (currently unused, reserved for future)
 * 
 * Returns:
 *   List of item_ids (as binaries) whose rules matched
 *   Empty list if no rules match
 *   List order is undefined (use enum sorting if order matters)
 * 
 * Example:
 *   {:ok, tree} = Atree.new()
 *   Atree.insert(tree, "rule_1", "amount > 100")
 *   Atree.insert(tree, "rule_2", "amount > 50")
 *   matches = Atree.match(tree, %{amount: 75})
 *   # Returns ["rule_2"] (only second rule matches)
 * 
 * Values Map Conversion:
 *   double    -> numeric constant
 *   string    -> string constant
 *   bool      -> boolean constant
 *   nil/atom  -> false
 * 
 * Error Handling:
 *   - Returns badarg if tree is invalid
 *   - Returns badarg if values is not a map
 *   - Rules with syntax errors cause that rule to fail matching
 * 
 * Performance:
 *   O(n * m) where n = rule count, m = average rule complexity
 *   Actual complexity depends on engine implementation
 *   Parser engine: linear scan with per-rule parsing
 *   Bytecode engine: faster for high rule counts (pre-compiled)
 */
static ERL_NIF_TERM nif_match(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) {
    GET_HANDLE(engine, 0)

    ValueMap values;
    if (!erlang_map_to_valuemap(env, argv[1], values)) {
        return enif_make_badarg(env);
    }

    auto matched_items = engine->match(values);

    auto list_terms = std::make_unique<ERL_NIF_TERM[]>(matched_items.size());
    for (size_t i = 0; i < matched_items.size(); ++i) {
        const std::string& item = matched_items[i];
        unsigned char* data = enif_make_new_binary(env, item.length(), &list_terms[i]);
        if (data) {
            std::memcpy(data, item.c_str(), item.length());
        }
    }

    ERL_NIF_TERM list = enif_make_list_from_array(env, list_terms.get(), matched_items.size());

    return list;
}

/**
 * Get all item IDs currently in the tree
 * 
 * NIF Signature: all_items/1
 * Elixir: Atree.all_items(tree)
 * 
 * Returns a list of all item IDs that have been inserted into the tree,
 * regardless of their rules. Useful for enumeration, debugging, or building
 * lists of all managed rules.
 * 
 * Arguments:
 *   argv[0]: Tree resource
 * 
 * Returns:
 *   List of item_ids (as binaries) in undefined order
 *   Empty list if tree is empty
 * 
 * Example:
 *   {:ok, tree} = Atree.new()
 *   Atree.insert(tree, "id1", "x > 10")
 *   Atree.insert(tree, "id2", "y == 20")
 *   ids = Atree.all_items(tree)
 *   # Returns ["id1", "id2"] or ["id2", "id1"]
 * 
 * Error Handling:
 *   - Returns badarg if tree is invalid
 * 
 * Performance:
 *   O(n) where n = number of items in tree
 *   Involves copying all item IDs from internal storage to Erlang terms
 * 
 * Memory:
 *   Creates new list terms on heap; garbage collected automatically
 */
static ERL_NIF_TERM nif_all_items(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) {
    GET_HANDLE(engine, 0)

    auto items = engine->all_items();

    auto list_terms = std::make_unique<ERL_NIF_TERM[]>(items.size());
    for (size_t i = 0; i < items.size(); ++i) {
        auto& item = items[i];
        auto* data = enif_make_new_binary(env, item.length(), &list_terms[i]);
        if (data) {
            std::memcpy(data, item.c_str(), item.length());
        }
    }

    ERL_NIF_TERM list = enif_make_list_from_array(env, list_terms.get(), items.size());

    return list;
}

/**
 * Get the number of items in the tree
 * 
 * NIF Signature: count/1
 * Elixir: Atree.count(tree)
 * 
 * Returns the total count of items (rules) currently stored in the tree.
 * 
 * Arguments:
 *   argv[0]: Tree resource
 * 
 * Returns:
 *   Non-negative integer (unsigned long)
 * 
 * Example:
 *   {:ok, tree} = Atree.new()
 *   count = Atree.count(tree)  # Returns 0
 *   Atree.insert(tree, "id", "true")
 *   count = Atree.count(tree)  # Returns 1
 * 
 * Error Handling:
 *   - Returns badarg if tree is invalid
 * 
 * Performance:
 *   O(1) if engine maintains exact count
 *   O(n) if engine needs to enumerate items
 */
static ERL_NIF_TERM nif_count(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) {
    GET_HANDLE(engine, 0)

    return enif_make_ulong(env, engine->count());
}

/**
 * Clear all items from the tree
 * 
 * NIF Signature: clear/1
 * Elixir: Atree.clear(tree)
 * 
 * Removes all items and rules from the tree, returning it to an empty state.
 * This is more efficient than repeatedly calling remove/2.
 * 
 * Arguments:
 *   argv[0]: Tree resource
 * 
 * Returns:
 *   :ok (always succeeds)
 * 
 * Side Effects:
 *   - All items deleted
 *   - All rules forgotten
 *   - Memory freed (depends on engine implementation)
 *   - Atree.empty?(tree) will return true after this call
 * 
 * Error Handling:
 *   - Returns badarg if tree is invalid
 *   - Otherwise always succeeds
 * 
 * Performance:
 *   O(n) where n = number of items being cleared
 *   May trigger bulk deallocation
 * 
 * Idempotency:
 *   Idempotent - calling clear/1 multiple times is safe
 */
static ERL_NIF_TERM nif_clear(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) {
    GET_HANDLE(engine, 0)

    engine->clear();
    return s_am_ok;
}

/**
 * Check if the tree is empty
 * 
 * NIF Signature: empty/1
 * Elixir: Atree.empty?(tree)
 * 
 * Determines whether the tree contains any items. Equivalent to count == 0
 * but may be more efficient depending on engine implementation.
 * 
 * Arguments:
 *   argv[0]: Tree resource
 * 
 * Returns:
 *   :true  if tree contains no items
 *   :false if tree contains at least one item
 * 
 * Example:
 *   {:ok, tree} = Atree.new()
 *   Atree.empty?(tree)           # Returns true
 *   Atree.insert(tree, "id", "x > 10")
 *   Atree.empty?(tree)           # Returns false
 * 
 * Error Handling:
 *   - Returns badarg if tree is invalid
 * 
 * Performance:
 *   O(1) if engine maintains a flag or count
 *   Should not require scanning all items
 * 
 * Relationship:
 *   empty?(tree) == (count(tree) == 0)
 */
static ERL_NIF_TERM nif_empty(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) {
    GET_HANDLE(engine, 0)

    bool is_empty = engine->empty();
    
    return is_empty ? s_am_true : s_am_false;
}

/**
 * Check if an item exists in the tree
 * 
 * NIF Signature: exists/2
 * Elixir: Atree.exists?(tree, item_id)
 * 
 * Determines whether a specific item ID is currently stored in the tree.
 * Useful for checking membership or guarding removal operations.
 * 
 * Arguments:
 *   argv[0]: Tree resource
 *   argv[1]: Item ID - binary/string to check
 * 
 * Returns:
 *   :true  if item_id was previously inserted and not yet removed
 *   :false if item_id not in tree or has been removed
 * 
 * Example:
 *   {:ok, tree} = Atree.new()
 *   Atree.exists?(tree, "id1")      # Returns false
 *   Atree.insert(tree, "id1", "true")
 *   Atree.exists?(tree, "id1")      # Returns true
 *   Atree.remove(tree, "id1")
 *   Atree.exists?(tree, "id1")      # Returns false
 * 
 * Use Cases:
 *   1. Idempotent remove:
 *      if exists?(tree, id), do: remove(tree, id)
 *   2. Update pattern (remove + insert):
 *      if exists?(tree, id), do: remove(tree, id)
 *      insert(tree, id, new_rule)
 *   3. Pre-check before insert to avoid item_exists error
 * 
 * Error Handling:
 *   - Returns badarg if tree is invalid
 *   - Otherwise always succeeds
 * 
 * Performance:
 *   O(1) average case (hash-based lookup)
 *   O(n) worst case (engine-dependent)
 */
static ERL_NIF_TERM nif_exists(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) {
    GET_HANDLE(engine, 0)

    ErlNifBinary item_id_bin;
    if (!enif_inspect_binary(env, argv[1], &item_id_bin)) {
        return enif_make_badarg(env);
    }
    std::string item_id((const char*)item_id_bin.data, item_id_bin.size);

    bool exists = engine->exists(item_id);
    
    return exists ? s_am_true : s_am_false;
}

/**
 * ============================================================================
 * NIF MODULE INITIALIZATION
 * ============================================================================
 */

/**
 * Native function dispatch table
 * 
 * Maps Erlang function names and arities to C++ implementations.
 * The NIF runtime uses this to route Erlang calls to the correct handler.
 * 
 * Entry format: {"function_name", arity, handler_function, flags}
 * - function_name: exported name in Elixir (or Erlang module)
 * - arity: number of arguments (allows overloading by arity)
 * - handler_function: C function to call
 * - flags: 0 for normal, ERL_NIF_DIRTY_* for CPU/IO intensive
 * 
 * Registered functions:
 *   new/0               Create empty tree with default engine
 *   new/1               Create tree with engine option
 *   insert/3            Add item with rule
 *   remove/2            Delete item from tree
 *   match/2             Find items matching values
 *   match/3             Find items (with options)
 *   all_items/1         Enumerate all item IDs
 *   count/1             Get item count
 *   clear/1             Remove all items
 *   empty/1             Check if tree is empty
 *   exists/2            Check if specific item exists
 * 
 * Note: The actual Elixir module wraps these with convenience functions
 * and guards that verify argument types before calling NIFs.
 */
static ErlNifFunc nif_funcs[] = {
    {"new",       0, nif_new,       0},
    {"new",       1, nif_new,       0},
    {"insert",    3, nif_insert,    0},
    {"remove",    2, nif_remove,    0},
    {"match",     2, nif_match,     0},
    {"match",     3, nif_match,     0},
    {"all_items", 1, nif_all_items, 0},
    {"count",     1, nif_count,     0},
    {"clear",     1, nif_clear,     0},
    {"empty",     1, nif_empty,     0},
    {"exists",    2, nif_exists,    0},
};

/**
 * Module load callback
 * 
 * Called by Erlang when the module is first loaded. Responsible for:
 * 1. Initializing global atom cache
 * 2. Creating Erlang resource types
 * 3. Setting up any module-level state
 * 
 * Atom caching strategy:
 *   - Atoms are immutable Erlang values used as constants
 *   - Creating atoms is expensive (hash table lookup)
 *   - Cache commonly used atoms in module load to avoid repeated creation
 *   - Cached atoms: ok, error, item_exists, not_found, true, false, etc.
 * 
 * Resource type registration:
 *   - Creates ERL_NIF_RT_CREATE resource type for rule_tree
 *   - Associates rule_tree_destructor callback for cleanup
 *   - Resource type is reused across module reloads if available
 * 
 * Arguments:
 *   env       Erlang NIF environment
 *   priv_data Pointer to module private data (unused here)
 *   load_info Erlang term passed to load() callback (unused here)
 * 
 * Returns:
 *   0 on success
 *   non-zero to abort module loading (prevents module from being loaded)
 */
static int load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info) {
    (void)priv_data;  // Unused parameter required by NIF interface
    (void)load_info;  // Unused parameter required by NIF interface
    
    // Initialize static atom variables
    s_am_ok          = enif_make_atom(env, "ok");
    s_am_error       = enif_make_atom(env, "error");
    s_am_item_exists = enif_make_atom(env, "item_exists");
    s_am_not_found   = enif_make_atom(env, "not_found");
    s_am_true        = enif_make_atom(env, "true");
    s_am_false       = enif_make_atom(env, "false");
    s_am_parser      = enif_make_atom(env, "parser");
    s_am_bytecode    = enif_make_atom(env, "bytecode");
    s_am_engine      = enif_make_atom(env, "engine");
    
    rule_tree_resource_type = enif_open_resource_type(
        env, NULL, "rule_tree", rule_tree_destructor,
        ERL_NIF_RT_CREATE, NULL
    );
    
    if (!rule_tree_resource_type) {
        return 1;
    }
    
    return 0;
}

/**
 * ============================================================================
 * NIF MODULE ENTRY POINT
 * ============================================================================
 */

/**
 * ERL_NIF_INIT - Erlang NIF module initialization macro
 * 
 * Macro expansion generates:
 *   - erl_nif_init() function that Erlang calls at module load
 *   - Searches for the function in atree_nif.so/.dll
 *   - Routes all calls through the dispatcher
 * 
 * Arguments:
 *   Module name (becomes Elixir.Atree in the NIF)
 *   Function table (nif_funcs array)
 *   Load callback (load function, called on first load)
 *   Reload callback (NULL - not used here)
 *   Upgrade callback (NULL - not used here)
 *   Unload callback (NULL - not used here)
 * 
 * Becomes:
 *   native compiled code accessible as Atree.new/0, Atree.insert/3, etc.
 */
ERL_NIF_INIT(Elixir.Atree, nif_funcs, load, NULL, NULL, NULL)

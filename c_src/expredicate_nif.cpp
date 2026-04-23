#include <erl_nif.h>
#include <cstring>
#include <memory>
#include <vector>
#include <map>
#include "expredicate.h"

using namespace expredicate;

// Resource type for RuleTree
static ErlNifResourceType* rule_tree_resource_type = nullptr;

// Static atom variables - initialized in load()
static ERL_NIF_TERM s_am_ok;
static ERL_NIF_TERM s_am_error;
static ERL_NIF_TERM s_am_item_exists;
static ERL_NIF_TERM s_am_not_found;
static ERL_NIF_TERM s_am_true;
static ERL_NIF_TERM s_am_false;

// Store raw pointer to RuleTree - Erlang resource manages lifetime
using rule_tree_handle = RuleTree*;

// Helper macro to extract handle from resource
#define GET_HANDLE(resource_ptr_var, argv_index) \
    rule_tree_handle* resource_ptr_mem = nullptr; \
    if (!enif_get_resource(env, argv[argv_index], rule_tree_resource_type, (void**)&resource_ptr_mem)) { \
        return enif_make_badarg(env); \
    } \
    if (!resource_ptr_mem) { \
        return enif_make_badarg(env); \
    } \
    rule_tree_handle resource_ptr_var = *resource_ptr_mem; \
    if (!resource_ptr_var) { \
        return enif_make_badarg(env); \
    }

/**
 * Destructor for RuleTree resource
 */
static void rule_tree_destructor(ErlNifEnv* env, void* obj) {
    (void)env;  // Unused parameter required by NIF interface
    // The resource memory contains a RuleTree pointer
    rule_tree_handle* resource_ptr = static_cast<rule_tree_handle*>(obj);
    if (resource_ptr) {
        RuleTree* tree = *resource_ptr;
        if (tree != nullptr) {
            try {
                delete tree;
            } catch (...) {
                // Ignore exceptions during cleanup
            }
            *resource_ptr = nullptr;
        }
    }
}

/**
 * Helper: Convert Erlang value to C++ Value
 */
static Value erlang_to_value(ErlNifEnv* env, ERL_NIF_TERM term) {
    // Try int64_t first
    ErlNifSInt64 i64v;
    if (enif_get_int64(env, term, &i64v)) {
        return Value(static_cast<int64_t>(i64v));
    }

    double dv;
    if (enif_get_double(env, term, &dv)) {
        return Value(dv);
    }

    unsigned len;
    if (enif_get_string_length(env, term, &len, ERL_NIF_LATIN1)) {
        std::string str(len + 1, '\0');
        enif_get_string(env, term, &str[0], len + 1, ERL_NIF_LATIN1);
        // Remove the null terminator from string (it's already there at position len)
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
 * Helper: Convert map from Erlang to C++
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
 * Create a new RuleTree
 * atree_nif:new() -> {ok, reference}
 */
static ERL_NIF_TERM nif_new(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    // Allocate Erlang-managed resource memory to hold a RuleTree pointer
    rule_tree_handle* resource_mem = (rule_tree_handle*)enif_alloc_resource(
        rule_tree_resource_type, sizeof(rule_tree_handle));
    
    if (!resource_mem) {
        return enif_make_badarg(env);
    }
    
    // Parse options if provided (argv[0] contains the options map)
    bool nocase = false;
    if (argc > 0) {
        // Check if argv[0] is a map with 'nocase' key
        int arity;
        if (enif_get_map_size(env, argv[0], (size_t*)&arity) >= 0) {
            ERL_NIF_TERM nocase_key = enif_make_atom(env, "nocase");
            ERL_NIF_TERM nocase_val;
            if (enif_get_map_value(env, argv[0], nocase_key, &nocase_val)) {
                // Check if the value is true
                if (enif_is_atom(env, nocase_val)) {
                    char atom_name[256];
                    if (enif_get_atom(env, nocase_val, atom_name, sizeof(atom_name), ERL_NIF_LATIN1) > 0) {
                        nocase = (strcmp(atom_name, "true") == 0);
                    }
                }
            }
        }
    }
    
    // Create the RuleTree on the heap with the nocase option
    *resource_mem = new RuleTree(nocase);
    
    // Create the Erlang resource term
    ERL_NIF_TERM result = enif_make_resource(env, resource_mem);
    
    // Release the resource - Erlang will call destructor when it's garbage collected
    enif_release_resource(resource_mem);
    
    return result;
}

/**
 * Insert an item with a rule
 * atree_nif:insert(Tree, ItemId, Rule) -> {ok, Tree} | {error, Reason}
 */
static ERL_NIF_TERM nif_insert(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) {
    GET_HANDLE(resource_ptr, 0)

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
        // metadata (tuple_elements[1]) is currently ignored, but could be stored in the future
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

    bool success = resource_ptr->insert(item_id, rule);

    if (success) {
        return enif_make_tuple2(env, s_am_ok, argv[0]);
    } else {
        return enif_make_tuple2(env, s_am_error, s_am_item_exists);
    }
}

/**
 * Remove an item
 * atree_nif:remove(Tree, ItemId) -> {ok, Tree} | {error, not_found}
 */
static ERL_NIF_TERM nif_remove(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) {
    GET_HANDLE(resource_ptr, 0)

    ErlNifBinary item_id_bin;
    if (!enif_inspect_binary(env, argv[1], &item_id_bin)) {
        return enif_make_badarg(env);
    }
    std::string item_id((const char*)item_id_bin.data, item_id_bin.size);

    bool found = resource_ptr->remove(item_id);
    
    if (found) {
        return enif_make_tuple2(env,
            s_am_ok,
            argv[0]
        );
    } else {
        return enif_make_tuple2(env,
            s_am_error,
            s_am_not_found
        );
    }
}

/**
 * Match a value map against all rules
 * atree_nif:match(Tree, ValueMap) -> {ok, [ItemIds]} | {error, invalid_map}
 */
static ERL_NIF_TERM nif_match(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) {
    GET_HANDLE(resource_ptr, 0)

    ValueMap values;
    if (!erlang_map_to_valuemap(env, argv[1], values)) {
        return enif_make_badarg(env);
    }

    auto matched_items = resource_ptr->match(values);

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
 * Get all item IDs
 * atree_nif:all_items(Tree) -> [ItemIds]
 */
static ERL_NIF_TERM nif_all_items(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) {
    GET_HANDLE(resource_ptr, 0)

    auto items = resource_ptr->all_items();

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
 * Get item count
 * atree_nif:count(Tree) -> {ok, Count}
 */
static ERL_NIF_TERM nif_count(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) {
    GET_HANDLE(resource_ptr, 0)

    return enif_make_ulong(env, resource_ptr->count());
}

/**
 * Clear the tree
 * atree_nif:clear(Tree) -> ok
 */
static ERL_NIF_TERM nif_clear(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) {
    GET_HANDLE(resource_ptr, 0)

    resource_ptr->clear();
    return s_am_ok;
}

/**
 * Check if empty
 * atree_nif:empty(Tree) -> Boolean
 */
static ERL_NIF_TERM nif_empty(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) {
    GET_HANDLE(resource_ptr, 0)

    bool is_empty = resource_ptr->empty();
    
    return is_empty ? s_am_true : s_am_false;
}

/**
 * Check if item exists
 * atree_nif:exists(Tree, ItemId) -> Boolean
 */
static ERL_NIF_TERM nif_exists(ErlNifEnv* env, int, const ERL_NIF_TERM argv[]) {
    GET_HANDLE(resource_ptr, 0)

    ErlNifBinary item_id_bin;
    if (!enif_inspect_binary(env, argv[1], &item_id_bin)) {
        return enif_make_badarg(env);
    }
    std::string item_id((const char*)item_id_bin.data, item_id_bin.size);

    bool exists = resource_ptr->exists(item_id);
    
    return exists ? s_am_true : s_am_false;
}

/**
 * Native functions table
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
 * Module initialization
 */
ERL_NIF_INIT(Elixir.Expredicate, nif_funcs, load, NULL, NULL, NULL)

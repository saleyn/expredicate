#pragma once

#include <algorithm>
#include <cctype>
#include <cmath>
#include <memory>
#include <mutex>
#include <shared_mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <variant>
#include <vector>
#include "xxhash.hpp"

/**
 * Synchronization Strategy Selection
 * 
 * Two options available:
 * 1. SHARED_MUTEX (default): std::shared_mutex + std::unordered_map
 *    - Simple, zero dependencies
 *    - Good for typical workloads
 * 
 * 2. GTL_PARALLEL_HASHMAP (when USE_GTL_PARALLEL_HASHMAP is defined):
 *    - Uses gtl::parallel_flat_hash_map with built-in lock-striping
 *    - ~40% faster for high-contention concurrent access
 *    - Better for future scaling to millions of rules
 * 
 * To use GTL, either:
 *   - Define -DUSE_GTL_PARALLEL_HASHMAP in compiler flags
 *   - Run: make all SYNC_STRATEGY=GTL (after make gtl-download)
 */

#ifdef USE_GTL_PARALLEL_HASHMAP
  #include <gtl/phmap.hpp>
#endif

// ============================================================================
// Custom Hash Functions
// ============================================================================

namespace expredicate {
  // Custom hash function for std::string using xxHash
  struct XXHashStringHasher {
    size_t operator()(const std::string& s) const noexcept {
      return xxh::xxhash<64>(s);
    }
  };
}

/**
 * Rule-based matching engine
 *
 * Stores opaque items with associated boolean expression rules.
 * The tree evaluates incoming value maps against all rules to find matches.
 */

namespace expredicate {

// Value type for rule evaluation
// Forward declare for recursive variant
struct ValueList;
using Value = std::variant<bool, int64_t, double, std::string, std::vector<std::string>>;
using ValueMap = std::unordered_map<std::string, Value, XXHashStringHasher>;


/**
 * Expression AST (Abstract Syntax Tree)
 */
class Expression {
public:
  enum class Type {
    LITERAL_BOOL,
    LITERAL_NUMBER,
    LITERAL_STRING,
    IDENTIFIER,
    BINARY_OP,
    UNARY_OP,
    IN_LIST,           // All elements check
    NOT_IN_LIST,       // All elements check
    ALL_IN_LIST,       // All elements check (explicit)
    ALL_NOT_IN_LIST,   // All elements check (explicit)
    ANY_IN_LIST,       // Any element check
    ANY_NOT_IN_LIST,   // Any element check
  };

  Type type;
  Value value;                         // For literals
  std::string op;                      // For operators
  std::vector<std::string> list_items; // For IN operator
  std::unique_ptr<Expression> left;
  std::unique_ptr<Expression> right;

  Expression(bool b) : type(Type::LITERAL_BOOL), value(b) {}
  Expression(int64_t i) : type(Type::LITERAL_NUMBER), value(i) {}
  Expression(double d) : type(Type::LITERAL_NUMBER), value(d) {}
  Expression(const std::string& s, Type t = Type::LITERAL_STRING)
    : type(t), value(s) {}

  static std::unique_ptr<Expression> make_bool(bool b) {
    return std::make_unique<Expression>(b);
  }

  static std::unique_ptr<Expression> make_number(int64_t i) {
    return std::make_unique<Expression>(i);
  }

  static std::unique_ptr<Expression> make_number(double d) {
    return std::make_unique<Expression>(d);
  }

  static std::unique_ptr<Expression> make_string(const std::string& s) {
    return std::make_unique<Expression>(s, Type::LITERAL_STRING);
  }

  static std::unique_ptr<Expression> make_identifier(const std::string& name) {
    return std::make_unique<Expression>(name, Type::IDENTIFIER);
  }

  static std::unique_ptr<Expression>
  make_binary_op(const std::string& op, std::unique_ptr<Expression> l,
                 std::unique_ptr<Expression> r) {
    auto expr = std::make_unique<Expression>(false);
    expr->type = Type::BINARY_OP;
    expr->op = op;
    expr->left = std::move(l);
    expr->right = std::move(r);
    return expr;
  }

  static std::unique_ptr<Expression>
  make_unary_op(const std::string& op, std::unique_ptr<Expression> operand) {
    auto expr = std::make_unique<Expression>(false);
    expr->type = Type::UNARY_OP;
    expr->op = op;
    expr->left = std::move(operand);
    return expr;
  }

  static std::unique_ptr<Expression>
  make_in_list(std::unique_ptr<Expression> operand,
               const std::vector<std::string> &items) {
    auto expr = std::make_unique<Expression>(false);
    expr->type = Type::IN_LIST;
    expr->left = std::move(operand);
    expr->list_items = items;
    std::sort(expr->list_items.begin(), expr->list_items.end());
    return expr;
  }

  static std::unique_ptr<Expression>
  make_all_in_list(std::unique_ptr<Expression> operand,
                   const std::vector<std::string> &items) {
    auto expr = std::make_unique<Expression>(false);
    expr->type = Type::ALL_IN_LIST;
    expr->left = std::move(operand);
    expr->list_items = items;
    std::sort(expr->list_items.begin(), expr->list_items.end());
    return expr;
  }

  static std::unique_ptr<Expression>
  make_not_in_list(std::unique_ptr<Expression> operand,
                   const std::vector<std::string> &items) {
    auto expr = std::make_unique<Expression>(false);
    expr->type = Type::NOT_IN_LIST;
    expr->left = std::move(operand);
    expr->list_items = items;
    std::sort(expr->list_items.begin(), expr->list_items.end());
    return expr;
  }

  static std::unique_ptr<Expression>
  make_all_not_in_list(std::unique_ptr<Expression> operand,
                       const std::vector<std::string> &items) {
    auto expr = std::make_unique<Expression>(false);
    expr->type = Type::ALL_NOT_IN_LIST;
    expr->left = std::move(operand);
    expr->list_items = items;
    std::sort(expr->list_items.begin(), expr->list_items.end());
    return expr;
  }

  static std::unique_ptr<Expression>
  make_any_in_list(std::unique_ptr<Expression> operand,
                   const std::vector<std::string> &items) {
    auto expr = std::make_unique<Expression>(false);
    expr->type = Type::ANY_IN_LIST;
    expr->left = std::move(operand);
    expr->list_items = items;
    std::sort(expr->list_items.begin(), expr->list_items.end());
    return expr;
  }

  static std::unique_ptr<Expression>
  make_any_not_in_list(std::unique_ptr<Expression> operand,
                       const std::vector<std::string> &items) {
    auto expr = std::make_unique<Expression>(false);
    expr->type = Type::ANY_NOT_IN_LIST;
    expr->left = std::move(operand);
    expr->list_items = items;
    std::sort(expr->list_items.begin(), expr->list_items.end());
    return expr;
  }
};

/**
 * Expression Parser and Evaluator
 */
class ExpressionEngine {
private:
  bool case_sensitive;

public:
  /**
   * Constructor with case sensitivity setting
   * @param case_sensitive true for case-sensitive comparisons (default), false for case-insensitive
   */
  explicit ExpressionEngine(bool case_sensitive = true) 
    : case_sensitive(case_sensitive) {}

  /**
   * Parse a rule string into an Expression tree
   */
  std::unique_ptr<Expression> parse(const std::string& rule) {
    Tokenizer tokenizer(rule);
    Parser parser(tokenizer.tokens);
    return parser.parse();
  }

  /**
   * Evaluate an expression against a value map
   */
  bool evaluate(const Expression* expr, const ValueMap& values) {
    if (!expr)
      return false;

    switch (expr->type) {
    case Expression::Type::LITERAL_BOOL:
      return std::get<bool>(expr->value);

    case Expression::Type::LITERAL_NUMBER:
    case Expression::Type::LITERAL_STRING:
      return true; // Non-false literals are truthy

    case Expression::Type::IDENTIFIER: {
      auto it = values.find(std::get<std::string>(expr->value));
      return (it != values.end()) && is_truthy(it->second);
    }

    case Expression::Type::UNARY_OP:
      return (expr->op == "not") && !evaluate(expr->left.get(), values);

    case Expression::Type::BINARY_OP:
      return evaluate_binary_op(expr, values);

    case Expression::Type::IN_LIST:
      return evaluate_in_list(expr, values);

    case Expression::Type::ALL_IN_LIST:
      return evaluate_in_list(expr, values);

    case Expression::Type::NOT_IN_LIST:
      return evaluate_not_in_list(expr, values);

    case Expression::Type::ALL_NOT_IN_LIST:
      return evaluate_not_in_list(expr, values);

    case Expression::Type::ANY_IN_LIST:
      return evaluate_any_in_list(expr, values);

    case Expression::Type::ANY_NOT_IN_LIST:
      return evaluate_any_not_in_list(expr, values);
    }

    return false;
  }

private:
  struct Tokenizer {
    std::vector<std::string> tokens;

    Tokenizer(const std::string& input) {
      std::string token;
      for (size_t i = 0; i < input.length(); ++i) {
        char c = input[i];

        if (std::isspace(c)) {
          if (!token.empty()) {
            tokens.push_back(token);
            token.clear();
          }
        } else if (c == '\'' || c == '"') {
          // String literal
          char quote = c;
          if (!token.empty()) {
            tokens.push_back(token);
            token.clear();
          }
          token += c;
          for (++i; i < input.length(); ++i) {
            token += input[i];
            if (input[i] == quote) {
              // Check if this quote is escaped by counting preceding
              // backslashes
              int backslash_count = 0;
              for (int j = static_cast<int>(i) - 1; j >= 0 && input[j] == '\\';
                   j--) {
                backslash_count++;
              }
              // If even number of backslashes (including 0), the quote is not
              // escaped
              if ((backslash_count & 1) == 0)
                break;
            }
          }
          tokens.push_back(token);
          token.clear();
        } else if (c == '[' || c == ']' || c == '(' || c == ')' || c == ',') {
          if (!token.empty()) {
            tokens.push_back(token);
            token.clear();
          }
          tokens.push_back(std::string(1, c));
        } else if (c == '>' || c == '<' || c == '=' || c == '!') {
          if (!token.empty()) {
            tokens.push_back(token);
            token.clear();
          }
          token += c;
          if (i + 1 < input.length() &&
              (input[i + 1] == '=' || (c == '<' && input[i + 1] == '>'))) {
            token += input[++i];
          }
          tokens.push_back(token);
          token.clear();
        } else {
          token += c;
        }
      }
      if (!token.empty()) {
        tokens.push_back(token);
      }
    }
  };

  struct Parser {
    std::vector<std::string> tokens;
    size_t pos = 0;

    Parser(const std::vector<std::string> &t) : tokens(t) {}

    std::unique_ptr<Expression> parse() { return parse_or(); }

  private:
    std::unique_ptr<Expression> parse_or() {
      auto left = parse_and();
      while (peek() == "or") {
        consume("or");
        auto right = parse_and();
        left = Expression::make_binary_op("or", std::move(left), std::move(right));
      }
      return left;
    }

    std::unique_ptr<Expression> parse_and() {
      auto left = parse_not();
      while (peek() == "and") {
        consume("and");
        auto right = parse_not();
        left = Expression::make_binary_op("and", std::move(left), std::move(right));
      }
      return left;
    }

    std::unique_ptr<Expression> parse_not() {
      if (peek() == "not" && peek_next() != "in") {
        consume("not");
        auto operand = parse_not();
        return Expression::make_unary_op("not", std::move(operand));
      }
      return parse_comparison();
    }

    std::unique_ptr<Expression> parse_comparison() {
      auto left = parse_primary();

      auto op_view = peek();
      if (op_view == ">"   || op_view == "<"   || op_view == ">=" || 
          op_view == "<="  || op_view == "=="  || op_view == "!=" ||
          op_view == "in"  || op_view == "not" ||
          op_view == "any" || op_view == "all") {

        if (op_view == "in") {
          consume("in");
          consume("[");
          std::vector<std::string> items;
          while (peek() != "]") {
            items.push_back(parse_string_literal());
            if (peek() == ",")
              consume(",");
          }
          consume("]");
          return Expression::make_in_list(std::move(left), items);
        } else if (op_view == "all" && peek_next() == "in") {
          consume("all");
          consume("in");
          consume("[");
          std::vector<std::string> items;
          while (peek() != "]") {
            items.push_back(parse_string_literal());
            if (peek() == ",")
              consume(",");
          }
          consume("]");
          return Expression::make_all_in_list(std::move(left), items);
        } else if (op_view == "any" && peek_next() == "in") {
          consume("any");
          consume("in");
          consume("[");
          std::vector<std::string> items;
          while (peek() != "]") {
            items.push_back(parse_string_literal());
            if (peek() == ",")
              consume(",");
          }
          consume("]");
          return Expression::make_any_in_list(std::move(left), items);
        } else if (op_view == "not" && peek_next() == "in") {
          consume("not");
          consume("in");
          consume("[");
          std::vector<std::string> items;
          while (peek() != "]") {
            items.push_back(parse_string_literal());
            if (peek() == ",")
              consume(",");
          }
          consume("]");
          return Expression::make_not_in_list(std::move(left), items);
        } else if (op_view == "all" && peek_next() == "not") {
          consume("all");
          consume("not");
          consume("in");
          consume("[");
          std::vector<std::string> items;
          while (peek() != "]") {
            items.push_back(parse_string_literal());
            if (peek() == ",")
              consume(",");
          }
          consume("]");
          return Expression::make_all_not_in_list(std::move(left), items);
        } else if (op_view == "any" && peek_next() == "not") {
          consume("any");
          consume("not");
          consume("in");
          consume("[");
          std::vector<std::string> items;
          while (peek() != "]") {
            items.push_back(parse_string_literal());
            if (peek() == ",")
              consume(",");
          }
          consume("]");
          return Expression::make_any_not_in_list(std::move(left), items);
        } else {
          std::string op(op_view);  // Convert to std::string for storage
          consume(op);
          auto right = parse_primary();
          return Expression::make_binary_op(op, std::move(left), std::move(right));
        }
      }

      return left;
    }

    std::unique_ptr<Expression> parse_primary() {
      auto token_view = peek();
      
      if (token_view.empty())
        throw std::runtime_error("Parse error: unexpected end of input");

      if (token_view == "(") {
        consume("(");
        auto expr = parse_or();
        consume(")");
        return expr;
      }

      if (token_view == "true") {
        consume("true");
        return Expression::make_bool(true);
      }

      if (token_view == "false") {
        consume("false");
        return Expression::make_bool(false);
      }

      if (token_view[0] == '\'' || token_view[0] == '"')
        return Expression::make_string(parse_string_literal());

      if (std::isdigit(token_view[0]) || (token_view[0] == '-' && token_view.length() > 1)) {
        std::string num_str = std::string(token_consume());
        size_t dot_pos = num_str.find('.');
        if (dot_pos == std::string::npos) {
          // Integer
          return Expression::make_number(static_cast<int64_t>(std::stoll(num_str)));
        } else {
          // Float
          return Expression::make_number(std::stod(num_str));
        }
      }

      // Identifier
      return Expression::make_identifier(std::string(token_consume()));
    }

    std::string parse_string_literal() {
      std::string token = token_consume();
      if (token.length() >= 2 && (token[0] == '\'' || token[0] == '"')) {
        std::string content = token.substr(1, token.length() - 2);
        // Unescape the content
        std::string unescaped;
        for (size_t i = 0; i < content.length(); ++i) {
          if (content[i] == '\\' && i + 1 < content.length()) {
            char next = content[i + 1];
            if (next == '\'' || next == '"' || next == '\\') {
              unescaped += next;
              i++; // Skip the next character
            } else {
              unescaped += content[i];
            }
          } else {
            unescaped += content[i];
          }
        }
        return unescaped;
      }
      return token;
    }

    std::string_view peek() { 
      return pos < tokens.size() ? std::string_view(tokens[pos]) : std::string_view(); 
    }

    std::string_view peek_next() {
      return pos + 1 < tokens.size() ? std::string_view(tokens[pos + 1]) : std::string_view();
    }

    std::string token_consume() {
      return pos < tokens.size() ? tokens[pos++] : "";
    }

    void consume(std::string_view expected) {
      if (peek() != expected) {
        throw std::runtime_error(std::string("Parse error: expected ") + std::string(expected));
      }
      pos++;
    }
  };

  bool is_truthy(const Value& v) const {
    if (std::holds_alternative<bool>(v))
      return std::get<bool>(v);
    if (std::holds_alternative<int64_t>(v))
      return std::get<int64_t>(v) != 0;
    if (std::holds_alternative<double>(v))
      return std::get<double>(v) != 0.0;
    if (std::holds_alternative<std::string>(v))
      return !std::get<std::string>(v).empty();
    return false;
  }

  bool evaluate_binary_op(const Expression* expr,
                          const ValueMap& values) {
    std::string_view op(expr->op);

    // For logical operators, evaluate operands as boolean expressions
    if (op == "and")
      return evaluate(expr->left.get(), values) && evaluate(expr->right.get(), values);
    if (op == "or")
      return evaluate(expr->left.get(), values) || evaluate(expr->right.get(), values);

    // For comparison operators, get and compare values
    auto left  = get_value(expr->left.get(), values);
    auto right = get_value(expr->right.get(), values);

    if (op == "==") return compare_equal(left, right);
    if (op == "!=") return !compare_equal(left, right);
    if (op == "<")  return compare_less(left, right);
    if (op == ">")  return compare_less(right, left);
    if (op == "<=") return !compare_less(right, left);
    if (op == ">=") return !compare_less(left, right);

    return false;
  }

  std::string value_to_string(const Value& val) const {
    if (std::holds_alternative<std::string>(val)) {
      return std::get<std::string>(val);
    } else if (std::holds_alternative<int64_t>(val)) {
      return std::to_string(std::get<int64_t>(val));
    } else if (std::holds_alternative<double>(val)) {
      double dval = std::get<double>(val);
      return dval == std::floor(dval)
           ? std::to_string(static_cast<long long>(dval))
           : std::to_string(dval);
    } else if (std::holds_alternative<bool>(val)) {
      return std::get<bool>(val) ? "true" : "false";
    }
    return "";
  }

  bool strings_equal_nocase(const std::string& a, const std::string& b) const {
    if (a.length() != b.length()) return false;
    return std::equal(a.begin(), a.end(), b.begin(),
                     [](unsigned char ca, unsigned char cb) {
                       return std::tolower(ca) == std::tolower(cb);
                     });
  }

  bool item_in_list_nocase(const std::string& item, const std::vector<std::string>& items) const {
    return std::any_of(items.begin(), items.end(),
                      [&item, this](const std::string& list_item) {
                        return strings_equal_nocase(item, list_item);
                      });
  }

  bool evaluate_in_list(const Expression* expr,
                        const ValueMap& values) {
    auto val = get_value(expr->left.get(), values);
    const auto& items = expr->list_items;

    // If value is a list, check that ALL elements are in the list (all in semantics)
    if (std::holds_alternative<std::vector<std::string>>(val)) {
      const auto& list = std::get<std::vector<std::string>>(val);
      return std::all_of(list.begin(), list.end(), [&items, this](const std::string& item) {
        if (case_sensitive) {
          return std::binary_search(items.begin(), items.end(), item);
        } else {
          return item_in_list_nocase(item, items);
        }
      });
    }

    // Single value: check if it's in the list
    std::string str_val = value_to_string(val);
    if (case_sensitive) {
      return std::binary_search(items.begin(), items.end(), str_val);
    } else {
      return item_in_list_nocase(str_val, items);
    }
  }

  bool evaluate_any_in_list(const Expression* expr,
                            const ValueMap& values) {
    auto val = get_value(expr->left.get(), values);
    const auto& items = expr->list_items;

    // If value is a list, check if ANY element is in the list
    if (std::holds_alternative<std::vector<std::string>>(val)) {
      const auto& list = std::get<std::vector<std::string>>(val);
      return std::any_of(list.begin(), list.end(), [&items, this](const std::string& item) {
        if (case_sensitive) {
          return std::binary_search(items.begin(), items.end(), item);
        } else {
          return item_in_list_nocase(item, items);
        }
      });
    }

    // Single value: same as IN_LIST
    std::string str_val = value_to_string(val);
    if (case_sensitive) {
      return std::binary_search(items.begin(), items.end(), str_val);
    } else {
      return item_in_list_nocase(str_val, items);
    }
  }

  bool evaluate_not_in_list(const Expression* expr,
                            const ValueMap& values) {
    auto val = get_value(expr->left.get(), values);
    const auto& items = expr->list_items;

    // If value is a list, check that ALL elements are NOT in the list (all not in semantics)
    if (std::holds_alternative<std::vector<std::string>>(val)) {
      const auto& list = std::get<std::vector<std::string>>(val);
      return std::all_of(list.begin(), list.end(), [&items, this](const std::string& item) {
        if (case_sensitive) {
          return !std::binary_search(items.begin(), items.end(), item);
        } else {
          return !item_in_list_nocase(item, items);
        }
      });
    }

    // Single value: check if it's NOT in the list
    std::string str_val = value_to_string(val);
    if (case_sensitive) {
      return !std::binary_search(items.begin(), items.end(), str_val);
    } else {
      return !item_in_list_nocase(str_val, items);
    }
  }

  bool evaluate_any_not_in_list(const Expression* expr,
                                const ValueMap& values) {
    auto val = get_value(expr->left.get(), values);
    const auto& items = expr->list_items;

    // If value is a list, check if ANY element is NOT in the list
    if (std::holds_alternative<std::vector<std::string>>(val)) {
      const auto& list = std::get<std::vector<std::string>>(val);
      return std::any_of(list.begin(), list.end(), [&items, this](const std::string& item) {
        if (case_sensitive) {
          return !std::binary_search(items.begin(), items.end(), item);
        } else {
          return !item_in_list_nocase(item, items);
        }
      });
    }

    // Single value: same as NOT_IN_LIST
    std::string str_val = value_to_string(val);
    if (case_sensitive) {
      return !std::binary_search(items.begin(), items.end(), str_val);
    } else {
      return !item_in_list_nocase(str_val, items);
    }
  }

  Value get_value(const Expression* expr,
                  const ValueMap& values) const {
    if (!expr)
      return false;

    if (expr->type == Expression::Type::IDENTIFIER) {
      auto it = values.find(std::get<std::string>(expr->value));
      return it != values.end() ? it->second : Value(false);
    }

    return expr->value;
  }

  bool compare_equal(const Value& a, const Value& b) const {
    if (std::holds_alternative<bool>(a) && std::holds_alternative<bool>(b))
      return std::get<bool>(a) == std::get<bool>(b);
    if (std::holds_alternative<int64_t>(a) && std::holds_alternative<int64_t>(b))
      return std::get<int64_t>(a) == std::get<int64_t>(b);
    if (std::holds_alternative<int64_t>(a) && std::holds_alternative<double>(b))
      return std::get<int64_t>(a) == std::get<double>(b);
    if (std::holds_alternative<double>(a) && std::holds_alternative<int64_t>(b))
      return std::get<double>(a) == std::get<int64_t>(b);
    if (std::holds_alternative<double>(a) &&
        std::holds_alternative<double>(b))
      return std::get<double>(a) == std::get<double>(b);
    if (std::holds_alternative<std::string>(a) &&
        std::holds_alternative<std::string>(b)) {
      const auto& sa = std::get<std::string>(a);
      const auto& sb = std::get<std::string>(b);
      if (case_sensitive) {
        return sa == sb;
      } else {
        // Case-insensitive comparison
        if (sa.length() != sb.length()) return false;
        return std::equal(sa.begin(), sa.end(), sb.begin(),
                         [](unsigned char ca, unsigned char cb) {
                           return std::tolower(ca) == std::tolower(cb);
                         });
      }
    }
    return false;
  }

  bool compare_less(const Value& a, const Value& b) const {
    if (std::holds_alternative<int64_t>(a) && std::holds_alternative<int64_t>(b))
      return std::get<int64_t>(a) < std::get<int64_t>(b);
    if (std::holds_alternative<int64_t>(a) && std::holds_alternative<double>(b))
      return std::get<int64_t>(a) < std::get<double>(b);
    if (std::holds_alternative<double>(a) && std::holds_alternative<int64_t>(b))
      return std::get<double>(a) < std::get<int64_t>(b);
    if (std::holds_alternative<double>(a) &&
        std::holds_alternative<double>(b))
      return std::get<double>(a) < std::get<double>(b);
    if (std::holds_alternative<std::string>(a) &&
        std::holds_alternative<std::string>(b))
      return std::get<std::string>(a) < std::get<std::string>(b);
    return false;
  }
};

/**
 * RuleTree: Stores items with rules and matches them against value maps
 * Thread-safe for concurrent access from Erlang schedulers
 */
class RuleTree {
public:
  // Lock type aliases - defined at class level for use in all methods
#ifdef USE_GTL_PARALLEL_HASHMAP
  // GTL is internally synchronized, use no-op lock types
  class NoOpLock {
  public:
    NoOpLock(const std::shared_mutex&) {} // Ignore the mutex
  };
  using unique_lock_type = NoOpLock;
  using shared_lock_type = NoOpLock;
#else
  using unique_lock_type = std::unique_lock<std::shared_mutex>;
  using shared_lock_type = std::shared_lock<std::shared_mutex>;
#endif

  explicit RuleTree(bool nocase = false) : case_sensitive(!nocase) {}

  // Getter for case sensitivity setting
  bool is_case_sensitive() const { return case_sensitive; }

  /**
   * Insert an item with a rule
   * @param item_id Opaque item identifier (string)
   * @param rule Boolean expression rule
   * @return true if inserted, false if item already exists
   */
  bool insert(const std::string& item_id, const std::string& rule) {
    unique_lock_type lock(rules_mutex);  // Exclusive lock
    
    if (rules.find(item_id) != rules.end()) {
      return false; // Item already exists
    }

    try {
      ExpressionEngine engine(case_sensitive);
      auto expr = engine.parse(rule);
      rules[item_id] = std::move(expr);
      return true;
    } catch (const std::exception&) {
      return false; // Parse error
    }
  }

  /**
   * Remove an item from the tree
   * @param item_id The item to remove
   * @return true if item was found and removed
   */
  bool remove(const std::string& item_id) {
    unique_lock_type lock(rules_mutex);  // Exclusive lock
    return rules.erase(item_id) > 0;
  }

  /**
   * Match a value map to find all matching items
   * @param values Map of variable names to values
   * @return Vector of matching item IDs
   */
  std::vector<std::string> match(const ValueMap& values) const {
    shared_lock_type lock(rules_mutex);  // Shared lock (read-only)
    ExpressionEngine engine(case_sensitive);
    std::vector<std::string> matches;

    for (const auto& [item_id, rule] : rules) {
      try {
        if (engine.evaluate(rule.get(), values))
          matches.push_back(item_id);
      } catch (const std::exception&) {
        // Skip items with evaluation errors
      }
    }

    return matches;
  }

  /**
   * Get all item IDs
   */
  std::vector<std::string> all_items() const {
    shared_lock_type lock(rules_mutex);  // Shared lock
    std::vector<std::string> items;
    for (const auto &[item_id, _] : rules)
      items.push_back(item_id);
    return items;
  }

  /**
   * Get count of items
   */
  size_t count() const {
    shared_lock_type lock(rules_mutex);  // Shared lock
    return rules.size();
  }

  /**
   * Check if empty
   */
  bool empty() const {
    shared_lock_type lock(rules_mutex);  // Shared lock
    return rules.empty();
  }

  /**
   * Clear all items
   */
  void clear() {
    unique_lock_type lock(rules_mutex);  // Exclusive lock
    rules.clear();
  }

  /**
   * Check if item exists
   */
  bool exists(const std::string& item_id) const {
    shared_lock_type lock(rules_mutex);  // Shared lock
    return rules.find(item_id) != rules.end();
  }

private:
#ifdef USE_GTL_PARALLEL_HASHMAP
  // GTL Strategy: Use parallel_flat_hash_map with built-in lock-striping
  // No separate mutex needed - GTL handles synchronization internally
  using hashmap = gtl::parallel_flat_hash_map<std::string, std::unique_ptr<Expression>>;
#else
  // SHARED_MUTEX Strategy (default): Use std::unordered_map with std::shared_mutex
  // Provides explicit reader-writer locking for concurrent access
  using hashmap = std::unordered_map<std::string, std::unique_ptr<Expression>, XXHashStringHasher>;
#endif
  hashmap rules;
  bool case_sensitive = true;  // true = case-sensitive (default), false = case-insensitive

  // Reader-writer lock: multiple readers or one writer (not used with GTL,
  // but included for API consistency)
  mutable std::shared_mutex rules_mutex;
};

} // namespace expredicate
#ifndef ATREE_H
#define ATREE_H

#include <cctype>
#include <cmath>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <variant>
#include <vector>

/**
 * Rule-based matching engine
 *
 * Stores opaque items with associated boolean expression rules.
 * The tree evaluates incoming value maps against all rules to find matches.
 */

namespace atree {

// Value type for rule evaluation
using Value = std::variant<bool, double, std::string>;
using ValueMap = std::unordered_map<std::string, Value>;

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
    IN_LIST,
    NOT_IN_LIST,
  };

  Type type;
  Value value;                         // For literals
  std::string op;                      // For operators
  std::vector<std::string> list_items; // For IN operator
  std::shared_ptr<Expression> left;
  std::shared_ptr<Expression> right;

  Expression(bool b) : type(Type::LITERAL_BOOL), value(b) {}
  Expression(double d) : type(Type::LITERAL_NUMBER), value(d) {}
  Expression(const std::string &s, Type t = Type::LITERAL_STRING)
    : type(t), value(s) {}

  static std::shared_ptr<Expression> make_bool(bool b) {
    return std::make_shared<Expression>(b);
  }

  static std::shared_ptr<Expression> make_number(double d) {
    return std::make_shared<Expression>(d);
  }

  static std::shared_ptr<Expression> make_string(const std::string &s) {
    return std::make_shared<Expression>(s, Type::LITERAL_STRING);
  }

  static std::shared_ptr<Expression> make_identifier(const std::string &name) {
    return std::make_shared<Expression>(name, Type::IDENTIFIER);
  }

  static std::shared_ptr<Expression>
  make_binary_op(const std::string &op, std::shared_ptr<Expression> l,
                 std::shared_ptr<Expression> r) {
    auto expr = std::make_shared<Expression>(false);
    expr->type = Type::BINARY_OP;
    expr->op = op;
    expr->left = l;
    expr->right = r;
    return expr;
  }

  static std::shared_ptr<Expression>
  make_unary_op(const std::string &op, std::shared_ptr<Expression> operand) {
    auto expr = std::make_shared<Expression>(false);
    expr->type = Type::UNARY_OP;
    expr->op = op;
    expr->left = operand;
    return expr;
  }

  static std::shared_ptr<Expression>
  make_in_list(std::shared_ptr<Expression> operand,
               const std::vector<std::string> &items) {
    auto expr = std::make_shared<Expression>(false);
    expr->type = Type::IN_LIST;
    expr->left = operand;
    expr->list_items = items;
    return expr;
  }

  static std::shared_ptr<Expression>
  make_not_in_list(std::shared_ptr<Expression> operand,
                   const std::vector<std::string> &items) {
    auto expr = std::make_shared<Expression>(false);
    expr->type = Type::NOT_IN_LIST;
    expr->left = operand;
    expr->list_items = items;
    return expr;
  }
};

/**
 * Expression Parser and Evaluator
 */
class ExpressionEngine {
public:
  /**
   * Parse a rule string into an Expression tree
   */
  static std::shared_ptr<Expression> parse(const std::string &rule) {
    Tokenizer tokenizer(rule);
    Parser parser(tokenizer.tokens);
    return parser.parse();
  }

  /**
   * Evaluate an expression against a value map
   */
  static bool evaluate(const std::shared_ptr<Expression> &expr,
                       const ValueMap &values) {
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
      if (it == values.end())
        return false;
      return is_truthy(it->second);
    }

    case Expression::Type::UNARY_OP:
      if (expr->op == "not") {
        return !evaluate(expr->left, values);
      }
      return false;

    case Expression::Type::BINARY_OP:
      return evaluate_binary_op(expr, values);

    case Expression::Type::IN_LIST:
      return evaluate_in_list(expr, values);

    case Expression::Type::NOT_IN_LIST:
      return evaluate_not_in_list(expr, values);
    }

    return false;
  }

private:
  struct Tokenizer {
    std::vector<std::string> tokens;

    Tokenizer(const std::string &input) {
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
              if ((backslash_count & 1) == 0) {
                break;
              }
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

    std::shared_ptr<Expression> parse() { return parse_or(); }

  private:
    std::shared_ptr<Expression> parse_or() {
      auto left = parse_and();
      while (peek() == "or") {
        consume("or");
        auto right = parse_and();
        left = Expression::make_binary_op("or", left, right);
      }
      return left;
    }

    std::shared_ptr<Expression> parse_and() {
      auto left = parse_not();
      while (peek() == "and") {
        consume("and");
        auto right = parse_not();
        left = Expression::make_binary_op("and", left, right);
      }
      return left;
    }

    std::shared_ptr<Expression> parse_not() {
      if (peek() == "not" && peek_next() != "in") {
        consume("not");
        auto operand = parse_not();
        return Expression::make_unary_op("not", operand);
      }
      return parse_comparison();
    }

    std::shared_ptr<Expression> parse_comparison() {
      auto left = parse_primary();

      auto op_view = peek();
      if (op_view == ">" || op_view == "<" || op_view == ">=" || op_view == "<=" || op_view == "==" ||
          op_view == "!=" || op_view == "in" || op_view == "not") {

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
          return Expression::make_in_list(left, items);
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
          return Expression::make_not_in_list(left, items);
        } else {
          std::string op(op_view);  // Convert to std::string for storage
          consume(op);
          auto right = parse_primary();
          return Expression::make_binary_op(op, left, right);
        }
      }

      return left;
    }

    std::shared_ptr<Expression> parse_primary() {
      auto token_view = peek();
      
      if (token_view.empty()) {
        throw std::runtime_error("Parse error: unexpected end of input");
      }

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

      if (token_view[0] == '\'' || token_view[0] == '"') {
        return Expression::make_string(parse_string_literal());
      }

      if (std::isdigit(token_view[0]) || (token_view[0] == '-' && token_view.length() > 1)) {
        return Expression::make_number(std::stod(std::string(token_consume())));
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

  static bool is_truthy(const Value &v) {
    if (std::holds_alternative<bool>(v)) {
      return std::get<bool>(v);
    }
    if (std::holds_alternative<double>(v)) {
      return std::get<double>(v) != 0.0;
    }
    if (std::holds_alternative<std::string>(v)) {
      return !std::get<std::string>(v).empty();
    }
    return false;
  }

  static bool evaluate_binary_op(const std::shared_ptr<Expression> &expr,
                                 const ValueMap &values) {
    std::string_view op(expr->op);

    // For logical operators, evaluate operands as boolean expressions
    if (op == "and") {
      return evaluate(expr->left, values) && evaluate(expr->right, values);
    }
    if (op == "or") {
      return evaluate(expr->left, values) || evaluate(expr->right, values);
    }

    // For comparison operators, get and compare values
    auto left = get_value(expr->left, values);
    auto right = get_value(expr->right, values);

    if (op == "==") {
      return compare_equal(left, right);
    }
    if (op == "!=") {
      return !compare_equal(left, right);
    }
    if (op == "<") {
      return compare_less(left, right);
    }
    if (op == ">") {
      return compare_less(right, left);
    }
    if (op == "<=") {
      return !compare_less(right, left);
    }
    if (op == ">=") {
      return !compare_less(left, right);
    }

    return false;
  }

  static bool evaluate_in_list(const std::shared_ptr<Expression> &expr,
                               const ValueMap &values) {
    auto val = get_value(expr->left, values);
    std::string str_val;

    if (std::holds_alternative<std::string>(val)) {
      str_val = std::get<std::string>(val);
    } else if (std::holds_alternative<double>(val)) {
      double dval = std::get<double>(val);
      // If the value is a whole number, convert as integer
      if (dval == std::floor(dval)) {
        str_val = std::to_string(static_cast<long long>(dval));
      } else {
        str_val = std::to_string(dval);
      }
    } else if (std::holds_alternative<bool>(val)) {
      str_val = std::get<bool>(val) ? "true" : "false";
    }

    for (const auto &item : expr->list_items) {
      if (item == str_val)
        return true;
    }
    return false;
  }

  static bool evaluate_not_in_list(const std::shared_ptr<Expression> &expr,
                                    const ValueMap &values) {
    return !evaluate_in_list(expr, values);
  }

  static Value get_value(const std::shared_ptr<Expression> &expr,
                         const ValueMap &values) {
    if (!expr)
      return false;

    if (expr->type == Expression::Type::IDENTIFIER) {
      auto it = values.find(std::get<std::string>(expr->value));
      return it != values.end() ? it->second : Value(false);
    }

    return expr->value;
  }

  static bool compare_equal(const Value &a, const Value &b) {
    if (std::holds_alternative<bool>(a) && std::holds_alternative<bool>(b)) {
      return std::get<bool>(a) == std::get<bool>(b);
    }
    if (std::holds_alternative<double>(a) &&
        std::holds_alternative<double>(b)) {
      return std::get<double>(a) == std::get<double>(b);
    }
    if (std::holds_alternative<std::string>(a) &&
        std::holds_alternative<std::string>(b)) {
      return std::get<std::string>(a) == std::get<std::string>(b);
    }
    return false;
  }

  static bool compare_less(const Value &a, const Value &b) {
    if (std::holds_alternative<double>(a) &&
        std::holds_alternative<double>(b)) {
      return std::get<double>(a) < std::get<double>(b);
    }
    if (std::holds_alternative<std::string>(a) &&
        std::holds_alternative<std::string>(b)) {
      return std::get<std::string>(a) < std::get<std::string>(b);
    }
    return false;
  }
};

/**
 * RuleTree: Stores items with rules and matches them against value maps
 */
class RuleTree {
public:
  RuleTree() {}

  /**
   * Insert an item with a rule
   * @param item_id Opaque item identifier (string)
   * @param rule Boolean expression rule
   * @return true if inserted, false if item already exists
   */
  bool insert(const std::string &item_id, const std::string &rule) {
    if (rules.find(item_id) != rules.end()) {
      return false; // Item already exists
    }

    try {
      auto expr = ExpressionEngine::parse(rule);
      rules[item_id] = expr;
      return true;
    } catch (const std::exception &) {
      return false; // Parse error
    }
  }

  /**
   * Remove an item from the tree
   * @param item_id The item to remove
   * @return true if item was found and removed
   */
  bool remove(const std::string &item_id) { return rules.erase(item_id) > 0; }

  /**
   * Match a value map to find all matching items
   * @param values Map of variable names to values
   * @return Vector of matching item IDs
   */
  std::vector<std::string> match(const ValueMap &values) const {
    std::vector<std::string> matches;

    for (const auto &[item_id, rule] : rules) {
      try {
        if (ExpressionEngine::evaluate(rule, values)) {
          matches.push_back(item_id);
        }
      } catch (const std::exception &) {
        // Skip items with evaluation errors
      }
    }

    return matches;
  }

  /**
   * Get all item IDs
   */
  std::vector<std::string> all_items() const {
    std::vector<std::string> items;
    for (const auto &[item_id, _] : rules) {
      items.push_back(item_id);
    }
    return items;
  }

  /**
   * Get count of items
   */
  size_t count() const { return rules.size(); }

  /**
   * Check if empty
   */
  bool empty() const { return rules.empty(); }

  /**
   * Clear all items
   */
  void clear() { rules.clear(); }

  /**
   * Check if item exists
   */
  bool exists(const std::string &item_id) const {
    return rules.find(item_id) != rules.end();
  }

  /**
   * Get rule for an item
   */
  std::shared_ptr<Expression> get_rule(const std::string &item_id) const {
    auto it = rules.find(item_id);
    return it != rules.end() ? it->second : nullptr;
  }

private:
  std::unordered_map<std::string, std::shared_ptr<Expression>> rules;
};

} // namespace atree

#endif // ATREE_H

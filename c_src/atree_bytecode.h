#ifndef ATREE_BYTECODE_H
#define ATREE_BYTECODE_H

#include <string>
#include <vector>
#include <memory>
#include <unordered_map>
#include <variant>
#include <cstring>
#include <cmath>
#include <stdexcept>

/**
 * Alternative implementation using bytecode compilation approach
 * (similar to ExprTK's approach)
 * 
 * This implementation compiles expressions to bytecode for potentially
 * faster evaluation, at the cost of more complex code and compilation overhead.
 */

namespace atree_bytecode {

using Value = std::variant<bool, double, std::string>;
using ValueMap = std::unordered_map<std::string, Value>;

// Bytecode instruction types
enum class OpCode {
  PUSH_BOOL,
  PUSH_DOUBLE,
  PUSH_STRING,
  PUSH_VAR,
  
  ADD, SUB, MUL, DIV, MOD,
  GT, LT, GTE, LTE, EQ, NEQ,
  AND, OR, NOT,
  IN_LIST,
  
  JMP, JMP_FALSE,
  POP,
  CALL_FUNCTION,
};

struct Instruction {
  OpCode op;
  double numeric_value = 0.0;
  std::string string_value;
  std::vector<std::string> list_items;
  int jump_target = 0;
  std::string var_name;
};

class BytecodeCompiler {
public:
  /**
   * Compile a rule string to bytecode
   */
  static std::vector<Instruction> compile(const std::string& rule) {
    Tokenizer tokenizer(rule);
    Parser parser(tokenizer.tokens);
    return parser.compile();
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
          char quote = c;
          if (!token.empty()) {
            tokens.push_back(token);
            token.clear();
          }
          token += c;
          for (++i; i < input.length(); ++i) {
            token += input[i];
            if (input[i] == quote) {
              int backslash_count = 0;
              for (int j = static_cast<int>(i) - 1; j >= 0 && input[j] == '\\'; j--) {
                backslash_count++;
              }
              if (backslash_count % 2 == 0) {
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
    std::vector<Instruction> code;

    Parser(const std::vector<std::string>& t) : tokens(t) {}

    std::vector<Instruction> compile() {
      parse_or();
      return code;
    }

  private:
    void parse_or() {
      parse_and();
      while (peek() == "or") {
        consume("or");
        parse_and();
        emit(OpCode::OR);
      }
    }

    void parse_and() {
      parse_not();
      while (peek() == "and") {
        consume("and");
        parse_not();
        emit(OpCode::AND);
      }
    }

    void parse_not() {
      if (peek() == "not") {
        consume("not");
        parse_not();
        emit(OpCode::NOT);
      } else {
        parse_comparison();
      }
    }

    void parse_comparison() {
      parse_primary();

      std::string op = peek();
      if (op == ">" || op == "<" || op == ">=" || op == "<=" || op == "==" ||
          op == "!=" || op == "in") {

        if (op == "in") {
          consume("in");
          consume("[");
          std::vector<std::string> items;
          while (peek() != "]") {
            items.push_back(parse_string_literal());
            if (peek() == ",")
              consume(",");
          }
          consume("]");
          Instruction instr;
          instr.op = OpCode::IN_LIST;
          instr.list_items = items;
          code.push_back(instr);
        } else {
          consume(op);
          parse_primary();
          
          OpCode opcode = OpCode::EQ;
          if (op == ">") opcode = OpCode::GT;
          else if (op == "<") opcode = OpCode::LT;
          else if (op == ">=") opcode = OpCode::GTE;
          else if (op == "<=") opcode = OpCode::LTE;
          else if (op == "==") opcode = OpCode::EQ;
          else if (op == "!=") opcode = OpCode::NEQ;
          
          emit(opcode);
        }
      }
    }

    void parse_primary() {
      std::string token = peek();

      if (token == "(") {
        consume("(");
        parse_or();
        consume(")");
      } else if (token == "true") {
        consume("true");
        emit(OpCode::PUSH_BOOL, 1.0);
      } else if (token == "false") {
        consume("false");
        emit(OpCode::PUSH_BOOL, 0.0);
      } else if (!token.empty() && (token[0] == '\'' || token[0] == '"')) {
        std::string str = parse_string_literal();
        Instruction instr;
        instr.op = OpCode::PUSH_STRING;
        instr.string_value = str;
        code.push_back(instr);
      } else if (!token.empty() && (std::isdigit(token[0]) || 
                 (token[0] == '-' && token.length() > 1))) {
        double val = std::stod(token_consume());
        emit(OpCode::PUSH_DOUBLE, val);
      } else {
        std::string var = token_consume();
        Instruction instr;
        instr.op = OpCode::PUSH_VAR;
        instr.var_name = var;
        code.push_back(instr);
      }
    }

    void emit(OpCode op) {
      Instruction instr;
      instr.op = op;
      code.push_back(instr);
    }

    void emit(OpCode op, double value) {
      Instruction instr;
      instr.op = op;
      instr.numeric_value = value;
      code.push_back(instr);
    }

    std::string parse_string_literal() {
      std::string token = token_consume();
      if (token.length() >= 2 && (token[0] == '\'' || token[0] == '"')) {
        std::string content = token.substr(1, token.length() - 2);
        std::string unescaped;
        for (size_t i = 0; i < content.length(); ++i) {
          if (content[i] == '\\' && i + 1 < content.length()) {
            char next = content[i + 1];
            if (next == '\'' || next == '"' || next == '\\') {
              unescaped += next;
              i++;
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

    std::string peek() { return pos < tokens.size() ? tokens[pos] : ""; }

    std::string token_consume() {
      return pos < tokens.size() ? tokens[pos++] : "";
    }

    void consume(const std::string& expected) {
      if (peek() != expected) {
        throw std::runtime_error("Parse error: expected " + expected);
      }
      pos++;
    }
  };
};

class BytecodeEvaluator {
public:
  static bool evaluate(const std::vector<Instruction>& code, const ValueMap& values) {
    BytecodeEvaluator eval(code, values);
    return eval.run();
  }

private:
  const std::vector<Instruction>& code;
  const ValueMap& values;
  std::vector<Value> stack;
  size_t pc = 0;

  BytecodeEvaluator(const std::vector<Instruction>& c, const ValueMap& v)
      : code(c), values(v) {}

  bool run() {
    while (pc < code.size()) {
      const Instruction& instr = code[pc++];
      
      switch (instr.op) {
      case OpCode::PUSH_BOOL:
        stack.push_back(instr.numeric_value != 0.0);
        break;
      case OpCode::PUSH_DOUBLE:
        stack.push_back(instr.numeric_value);
        break;
      case OpCode::PUSH_STRING:
        stack.push_back(instr.string_value);
        break;
      case OpCode::PUSH_VAR: {
        auto it = values.find(instr.var_name);
        if (it != values.end()) {
          stack.push_back(it->second);
        } else {
          stack.push_back(false);
        }
        break;
      }
      case OpCode::GT: {
        auto right = pop_double();
        auto left = pop_double();
        stack.push_back(left > right);
        break;
      }
      case OpCode::LT: {
        auto right = pop_double();
        auto left = pop_double();
        stack.push_back(left < right);
        break;
      }
      case OpCode::GTE: {
        auto right = pop_double();
        auto left = pop_double();
        stack.push_back(left >= right);
        break;
      }
      case OpCode::LTE: {
        auto right = pop_double();
        auto left = pop_double();
        stack.push_back(left <= right);
        break;
      }
      case OpCode::EQ: {
        auto right = stack.back(); stack.pop_back();
        auto left = stack.back(); stack.pop_back();
        stack.push_back(compare_equal(left, right));
        break;
      }
      case OpCode::NEQ: {
        auto right = stack.back(); stack.pop_back();
        auto left = stack.back(); stack.pop_back();
        stack.push_back(!compare_equal(left, right));
        break;
      }
      case OpCode::AND: {
        auto right = is_truthy(stack.back()); stack.pop_back();
        auto left = is_truthy(stack.back()); stack.pop_back();
        stack.push_back(left && right);
        break;
      }
      case OpCode::OR: {
        auto right = is_truthy(stack.back()); stack.pop_back();
        auto left = is_truthy(stack.back()); stack.pop_back();
        stack.push_back(left || right);
        break;
      }
      case OpCode::NOT: {
        auto val = is_truthy(stack.back()); stack.pop_back();
        stack.push_back(!val);
        break;
      }
      case OpCode::IN_LIST: {
        auto val = stack.back(); stack.pop_back();
        std::string str_val;
        if (std::holds_alternative<std::string>(val)) {
          str_val = std::get<std::string>(val);
        } else if (std::holds_alternative<double>(val)) {
          str_val = std::to_string(std::get<double>(val));
        }
        bool found = false;
        for (const auto& item : instr.list_items) {
          if (item == str_val) {
            found = true;
            break;
          }
        }
        stack.push_back(found);
        break;
      }
      default:
        break;
      }
    }

    return is_truthy(stack.empty() ? Value(false) : stack.back());
  }

  double pop_double() {
    auto val = stack.back();
    stack.pop_back();
    if (std::holds_alternative<double>(val)) {
      return std::get<double>(val);
    }
    return 0.0;
  }

  bool is_truthy(const Value& v) {
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

  bool compare_equal(const Value& a, const Value& b) {
    if (std::holds_alternative<bool>(a) && std::holds_alternative<bool>(b)) {
      return std::get<bool>(a) == std::get<bool>(b);
    }
    if (std::holds_alternative<double>(a) && std::holds_alternative<double>(b)) {
      return std::get<double>(a) == std::get<double>(b);
    }
    if (std::holds_alternative<std::string>(a) && std::holds_alternative<std::string>(b)) {
      return std::get<std::string>(a) == std::get<std::string>(b);
    }
    return false;
  }
};

class RuleTreeBytecode {
public:
  bool insert(const std::string& item_id, const std::string& rule) {
    if (rules.find(item_id) != rules.end()) {
      return false;
    }

    try {
      auto bytecode = BytecodeCompiler::compile(rule);
      rules[item_id] = bytecode;
      return true;
    } catch (const std::exception&) {
      return false;
    }
  }

  bool remove(const std::string& item_id) {
    return rules.erase(item_id) > 0;
  }

  std::vector<std::string> match(const ValueMap& values) const {
    std::vector<std::string> matches;

    for (const auto& [item_id, bytecode] : rules) {
      try {
        if (BytecodeEvaluator::evaluate(bytecode, values)) {
          matches.push_back(item_id);
        }
      } catch (const std::exception&) {
        // Skip items with evaluation errors
      }
    }

    return matches;
  }

  std::vector<std::string> all_items() const {
    std::vector<std::string> items;
    for (const auto& [item_id, _] : rules) {
      items.push_back(item_id);
    }
    return items;
  }

  size_t count() const {
    return rules.size();
  }

  bool empty() const {
    return rules.empty();
  }

  void clear() {
    rules.clear();
  }

  bool exists(const std::string& item_id) const {
    return rules.find(item_id) != rules.end();
  }

private:
  std::unordered_map<std::string, std::vector<Instruction>> rules;
};

} // namespace atree_bytecode

#endif // ATREE_BYTECODE_H

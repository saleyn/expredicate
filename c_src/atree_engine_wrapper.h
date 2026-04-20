#ifndef ATREE_ENGINE_WRAPPER_H
#define ATREE_ENGINE_WRAPPER_H

#include <memory>
#include <string>
#include <vector>
#include <variant>
#include "atree.h"
#include "atree_bytecode.h"

/**
 * Abstraction layer to support multiple expression engines
 * Allows runtime selection between custom parser and bytecode VM
 */

namespace atree {

enum class EngineType {
  PARSER,    // Custom recursive descent parser (default)
  BYTECODE   // Bytecode virtual machine (high-volume optimization)
};

/**
 * Expression engine interface
 * Virtual base for both implementations
 */
class ExpressionEngineInterface {
public:
  virtual ~ExpressionEngineInterface() = default;
  
  virtual bool insert(const std::string& item_id, const std::string& rule) = 0;
  virtual bool remove(const std::string& item_id) = 0;
  virtual std::vector<std::string> match(const ValueMap& values) const = 0;
  virtual std::vector<std::string> all_items() const = 0;
  virtual size_t count() const = 0;
  virtual bool empty() const = 0;
  virtual void clear() = 0;
  virtual bool exists(const std::string& item_id) const = 0;
  virtual EngineType type() const = 0;
};

/**
 * Wrapper for custom recursive descent parser
 */
class ParserEngineWrapper : public ExpressionEngineInterface {
private:
  RuleTree impl;

public:
  ParserEngineWrapper() {}

  bool insert(const std::string& item_id, const std::string& rule) override {
    return impl.insert(item_id, rule);
  }

  bool remove(const std::string& item_id) override {
    return impl.remove(item_id);
  }

  std::vector<std::string> match(const ValueMap& values) const override {
    return impl.match(values);
  }

  std::vector<std::string> all_items() const override {
    return impl.all_items();
  }

  size_t count() const override {
    return impl.count();
  }

  bool empty() const override {
    return impl.empty();
  }

  void clear() override {
    impl.clear();
  }

  bool exists(const std::string& item_id) const override {
    return impl.exists(item_id);
  }

  EngineType type() const override {
    return EngineType::PARSER;
  }
};

/**
 * Wrapper for bytecode virtual machine
 */
class BytecodeEngineWrapper : public ExpressionEngineInterface {
private:
  atree_bytecode::RuleTreeBytecode impl;

public:
  BytecodeEngineWrapper() {}

  bool insert(const std::string& item_id, const std::string& rule) override {
    return impl.insert(item_id, rule);
  }

  bool remove(const std::string& item_id) override {
    return impl.remove(item_id);
  }

  std::vector<std::string> match(const ValueMap& values) const override {
    // Convert ValueMap to bytecode ValueMap
    atree_bytecode::ValueMap bc_values;
    for (const auto& [k, v] : values) {
      atree_bytecode::Value bc_val;
      if (std::holds_alternative<bool>(v)) {
        bc_val = std::get<bool>(v);
      } else if (std::holds_alternative<double>(v)) {
        bc_val = std::get<double>(v);
      } else if (std::holds_alternative<std::string>(v)) {
        bc_val = std::get<std::string>(v);
      }
      bc_values[k] = bc_val;
    }
    return impl.match(bc_values);
  }

  std::vector<std::string> all_items() const override {
    return impl.all_items();
  }

  size_t count() const override {
    return impl.count();
  }

  bool empty() const override {
    return impl.empty();
  }

  void clear() override {
    impl.clear();
  }

  bool exists(const std::string& item_id) const override {
    return impl.exists(item_id);
  }

  EngineType type() const override {
    return EngineType::BYTECODE;
  }
};

/**
 * Factory function to create engine instances
 */
inline std::unique_ptr<ExpressionEngineInterface> create_engine(EngineType type) {
  switch (type) {
  case EngineType::BYTECODE:
    return std::make_unique<BytecodeEngineWrapper>();
  case EngineType::PARSER:
  default:
    return std::make_unique<ParserEngineWrapper>();
  }
}

} // namespace atree

#endif // ATREE_ENGINE_WRAPPER_H

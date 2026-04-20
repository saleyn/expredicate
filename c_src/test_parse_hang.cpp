#include <iostream>
#include <string>
#include "../c_src/atree.h"

using namespace atree;

int main() {
    std::cout << "Testing tokenization and parsing..." << std::endl;
    
    std::string rule = "c in [\"a\", \"b\", \"c\"]";
    std::cout << "Rule: " << rule << std::endl;
    
    try {
        std::cout << "Starting parse..." << std::endl;
        auto expr = ExpressionEngine::parse(rule);
        std::cout << "Parse successful!" << std::endl;
        
        if (expr && expr->type == Expression::Type::IN_LIST) {
            std::cout << "Expression is IN_LIST" << std::endl;
            std::cout << "Items in list:" << std::endl;
            for (const auto& item : expr->list_items) {
                std::cout << "  - " << item << std::endl;
            }
        }
    } catch (const std::exception& e) {
        std::cout << "Parse failed with exception: " << e.what() << std::endl;
    }
    
    return 0;
}

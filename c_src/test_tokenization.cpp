#include <iostream>
#include <string>
#include <cstring>
#include "atree.h"

using namespace atree;

int main() {
    std::cout << "Testing tokenization step by step..." << std::endl;
    
    // Test 1: Simple rule
    std::string rule1 = "c in [\"a\", \"b\", \"c\"]";
    std::cout << "\nRule 1 (C++ string): " << rule1 << std::endl;
    std::cout << "Rule 1 length: " << rule1.length() << std::endl;
    std::cout << "Rule 1 char codes: ";
    for (char c : rule1) {
        std::cout << (int)(unsigned char)c << " ";
    }
    std::cout << std::endl;
    
    std::cout << "Parsing rule 1..." << std::endl;
    try {
        auto expr1 = ExpressionEngine::parse(rule1);
        std::cout << "Rule 1 parsed successfully!" << std::endl;
    } catch (const std::exception& e) {
        std::cout << "Rule 1 parse failed: " << e.what() << std::endl;
    }
    
    // Test 2: With binary data (simulating what the NIF does)
    std::cout << "\nRule 2 (from binary): ";
    const char* binary_data = "c in [\"a\", \"b\", \"c\"]";
    size_t binary_size = strlen(binary_data);
    std::string rule2(binary_data, binary_size);
    std::cout << rule2 << std::endl;
    std::cout << "Rule 2 length: " << rule2.length() << std::endl;
    
    std::cout << "Parsing rule 2..." << std::endl;
    try {
        auto expr2 = ExpressionEngine::parse(rule2);
        std::cout << "Rule 2 parsed successfully!" << std::endl;
    } catch (const std::exception& e) {
        std::cout << "Rule 2 parse failed: " << e.what() << std::endl;
    }
    
    std::cout << "\nAll tests completed!" << std::endl;
    return 0;
}

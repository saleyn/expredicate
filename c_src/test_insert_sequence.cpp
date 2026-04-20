#include <iostream>
#include <memory>
#include "atree.h"

using namespace atree;

int main() {
    std::cout << "Creating rule tree..." << std::endl;
    RuleTree tree;
    std::cout << "Inserting rule 1: a > 10" << std::endl;
    tree.insert("abc", "a > 10");
    std::cout << "Inserting rule 2: b > 20" << std::endl;
    tree.insert("bcd", "b > 20");
    std::cout << "Inserting rule 3: c in [\"a\", \"b\", \"c\"]" << std::endl;
    tree.insert("efg", "c in [\"a\", \"b\", \"c\"]");
    std::cout << "All inserts successful!" << std::endl;
    return 0;
}

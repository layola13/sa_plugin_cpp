#include <iostream>

int getN() { return 1; }

int main() {
    std::cout << (true == getN()) << std::endl;
    std::cout << (false != getN()) << std::endl;
    return 0;
}

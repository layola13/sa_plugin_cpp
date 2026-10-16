#include <iostream>

int main() {
    std::cout << (1 << 0) << std::endl;
    std::cout << (1 << 31) << std::endl;
    std::cout << (1 >> 31) << std::endl;
    std::cout << (-1 >> 31) << std::endl;
    return 0;
}

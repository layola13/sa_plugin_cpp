#include <iostream>

int main() {
    std::cout << ((1 << 31) >> 1) << std::endl;
    std::cout << (0 - 1) << std::endl;
    std::cout << (~0) << std::endl;
    std::cout << (-2147483647 - 1) << std::endl;
    return 0;
}

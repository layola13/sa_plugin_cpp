#include <iostream>

int main() {
    std::cout << (1 << 31 << 1) << std::endl;
    std::cout << ((1 << 31) >> 31) << std::endl;
    return 0;
}

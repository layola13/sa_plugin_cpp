#include <iostream>

int main() {
    std::cout << ((1 << 4) + (16 >> 2)) << std::endl;
    std::cout << ((1 << 31) == -2147483647 - 1 ? 1 : 0) << std::endl;
    return 0;
}

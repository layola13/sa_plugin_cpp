#include <iostream>

int main() {
    int a = -5;
    std::cout << (a < 0 ? -a : a) << std::endl;
    std::cout << 4 << std::endl;
    std::cout << 4 << std::endl;
    int m1 = 3 < 8 ? 3 : 8;
    std::cout << m1 << std::endl;
    int m2 = 3 > 8 ? 3 : 8;
    std::cout << m2 << std::endl;
    return 0;
}

#include <iostream>

int main() {
    long big = 1000000;
    big = big * 1000;
    std::cout << (big == 1000000000) << std::endl;
    const int k = 7;
    auto doubled = k * 2;
    std::cout << doubled << std::endl;
    unsigned u = 5;
    std::cout << u + 1 << std::endl;
    return 0;
}

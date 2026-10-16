#include <iostream>

int main() {
    int a = 12;
    a &= 10;
    std::cout << a << std::endl;
    int b = 12;
    b |= 10;
    std::cout << b << std::endl;
    int c = 12;
    c ^= 10;
    std::cout << c << std::endl;
    return 0;
}

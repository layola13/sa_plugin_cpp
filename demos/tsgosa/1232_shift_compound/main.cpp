#include <iostream>

int main() {
    int a = 1;
    a <<= 31;
    std::cout << a << std::endl;
    int b = -16;
    b >>= 1;
    std::cout << b << std::endl;
    return 0;
}

#include <iostream>

int main() {
    int a = 5;
    int b = 9;
    a ^= b;
    b ^= a;
    a ^= b;
    std::cout << a << std::endl;
    std::cout << b << std::endl;
    return 0;
}

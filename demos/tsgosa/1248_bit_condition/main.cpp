#include <iostream>

int main() {
    const int x = 5;
    if (x & 1) { std::cout << 1 << std::endl; } else { std::cout << 0 << std::endl; }
    if (x & 2) { std::cout << 1 << std::endl; } else { std::cout << 0 << std::endl; }
    return 0;
}

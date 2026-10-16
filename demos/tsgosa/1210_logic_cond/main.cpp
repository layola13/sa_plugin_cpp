#include <iostream>

int main() {
    if (3 && 4) { std::cout << 1 << std::endl; } else { std::cout << 0 << std::endl; }
    if (0 && 4) { std::cout << 1 << std::endl; } else { std::cout << 0 << std::endl; }
    if (0 || 4) { std::cout << 1 << std::endl; } else { std::cout << 0 << std::endl; }
    if (3 || 0) { std::cout << 1 << std::endl; } else { std::cout << 0 << std::endl; }
    return 0;
}

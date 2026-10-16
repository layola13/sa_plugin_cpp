#include <iostream>

int main() {
    if ((1 << 31) < 0) { std::cout << 1 << std::endl; } else { std::cout << 0 << std::endl; }
    return 0;
}

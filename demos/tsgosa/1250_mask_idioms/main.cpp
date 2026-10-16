#include <iostream>

int main() {
    const int x = 255;
    std::cout << (x & 0xFF) << std::endl;
    std::cout << (x | 0x100) << std::endl;
    return 0;
}

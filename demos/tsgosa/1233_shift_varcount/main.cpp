#include <iostream>

int main() {
    const int k = 3;
    std::cout << (1 << k) << std::endl;
    std::cout << (16 >> k) << std::endl;
    return 0;
}

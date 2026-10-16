#include <iostream>

int max(int a, int b) {
    return a > b ? a : b;
}

int main() {
    std::cout << max(3, 7) << std::endl;
    std::cout << max(9, 2) << std::endl;
    return 0;
}

#include <iostream>

int max2(int a, int b) {
    return a > b ? a : b;
}

int main() {
    std::cout << max2(3, 7) << std::endl;
    std::cout << max2(9, 2) << std::endl;
    int x = -5;
    int absx = x < 0 ? -x : x;
    std::cout << absx << std::endl;
    return 0;
}

#include <iostream>

int add(int a, int b) {
    return a + b;
}

int mul(int a, int b) {
    return a * b;
}

int main() {
    std::cout << add(mul(2, 3), mul(4, 5)) << std::endl;
    return 0;
}

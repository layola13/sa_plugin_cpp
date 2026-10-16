#include <iostream>

int add3(int a, int b, int c) {
    return a + b + c;
}

int fact(int n) {
    if (n <= 1) {
        return 1;
    }
    return n * fact(n - 1);
}

int main() {
    std::cout << add3(1, 2, 3) << std::endl;
    std::cout << fact(6) << std::endl;
    return 0;
}

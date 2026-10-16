#include <iostream>

int fib(int n) {
    if (n <= 1) {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

int main() {
    std::cout << fib(10) << std::endl;
    std::cout << fib(8) << std::endl;
    return 0;
}

#include <iostream>

int isPrime(int n) {
    if (n < 2) {
        return 0;
    }
    for (int i = 2; i * i <= n; i++) {
        if (n % i == 0) {
            return 0;
        }
    }
    return 1;
}

int main() {
    int c = 0;
    for (int i = 2; i < 30; i++) {
        c = c + isPrime(i);
    }
    std::cout << c << std::endl;
    return 0;
}

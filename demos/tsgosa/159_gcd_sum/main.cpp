#include <iostream>

int gcd(int a, int b) {
    while (b != 0) {
        int t = a % b;
        a = b;
        b = t;
    }
    return a;
}

int main() {
    int t = 0;
    for (int i = 1; i <= 10; i++) {
        t = t + gcd(i, 12);
    }
    std::cout << t << std::endl;
    return 0;
}

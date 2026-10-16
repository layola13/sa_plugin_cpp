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
    std::cout << gcd(12, 8) << " " << gcd(100, 75) << " " << gcd(17, 5) << std::endl;
    return 0;
}

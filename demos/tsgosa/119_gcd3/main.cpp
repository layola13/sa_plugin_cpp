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
    std::cout << gcd(48, 18) << " " << gcd(7, 13) << std::endl;
    return 0;
}

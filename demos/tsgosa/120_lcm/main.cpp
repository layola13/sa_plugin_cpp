#include <iostream>

int gcd(int a, int b) {
    if (b == 0) {
        return a;
    }
    return gcd(b, a % b);
}

int main() {
    int g = gcd(48, 18);
    std::cout << g << " " << (48 / g) * 18 << std::endl;
    return 0;
}

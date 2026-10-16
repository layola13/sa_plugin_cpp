#include <iostream>

int clamp(int x, int lo, int hi) {
    int m = x > lo ? x : lo;
    return m < hi ? m : hi;
}

int main() {
    std::cout << clamp(5, 1, 10) << " " << clamp(-3, 1, 10) << " " << clamp(99, 1, 10) << std::endl;
    return 0;
}

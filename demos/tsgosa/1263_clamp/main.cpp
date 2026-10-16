#include <iostream>

int clamp(int v, int lo, int hi) {
    if (v < lo) { return lo; }
    if (v > hi) { return hi; }
    return v;
}

int main() {
    std::cout << clamp(5, 0, 10) << std::endl;
    std::cout << clamp(-5, 0, 10) << std::endl;
    std::cout << clamp(50, 0, 10) << std::endl;
    return 0;
}

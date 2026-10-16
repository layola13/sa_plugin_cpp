#include <iostream>

int between(int v, int lo, int hi) {
    return v >= lo && v <= hi ? 1 : 0;
}

int main() {
    std::cout << between(5, 0, 10) << std::endl;
    std::cout << between(-1, 0, 10) << std::endl;
    std::cout << between(11, 0, 10) << std::endl;
    return 0;
}

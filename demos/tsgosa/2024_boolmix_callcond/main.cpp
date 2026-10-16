#include <iostream>

int getN() { return 1; }

int main() {
    bool f = true;
    if (f == getN()) { std::cout << 1 << std::endl; } else { std::cout << 0 << std::endl; }
    return 0;
}

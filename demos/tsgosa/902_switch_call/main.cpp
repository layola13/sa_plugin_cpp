#include <iostream>

int kind(int v) {
    return v;
}

int main() {
    const int x = 2;
    switch (kind(x)) {
        case 1: std::cout << 1 << std::endl; break;
        case 2: std::cout << 2 << std::endl; break;
        default: std::cout << 0 << std::endl;
    }
    return 0;
}

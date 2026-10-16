#include <iostream>

int main() {
    bool f = true;
    switch (f) {
        case 1: std::cout << 1 << std::endl; break;
        default: std::cout << 0 << std::endl; break;
    }
    return 0;
}

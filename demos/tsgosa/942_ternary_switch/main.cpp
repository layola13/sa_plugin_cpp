#include <iostream>

int main() {
    const bool f = true;
    switch (f ? 1 : 0) {
        case 1: std::cout << 7 << std::endl; break;
        default: std::cout << 0 << std::endl;
    }
    return 0;
}

#include <iostream>

int k() {
    return 2;
}

int main() {
    if (k() == 1) {
        std::cout << 1 << std::endl;
    } else if (k() == 2) {
        std::cout << 2 << std::endl;
    } else {
        std::cout << 3 << std::endl;
    }
    return 0;
}

#include <iostream>

int k() {
    return 2;
}

int main() {
    switch (k()) {
        case 1:
            std::cout << 1 << std::endl;
            break;
        case 2:
            std::cout << 2 << std::endl;
            break;
        default:
            std::cout << 0 << std::endl;
    }
    return 0;
}

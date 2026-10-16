#include <iostream>

int main() {
    int day = 3;
    switch (day) {
        case 1:
            std::cout << 10 << std::endl;
            break;
        case 3:
            std::cout << 30 << std::endl;
            break;
        default:
            std::cout << 99 << std::endl;
            break;
    }
    int x = 2;
    switch (x) {
        case 1:
            std::cout << 1 << std::endl;
            break;
        default:
            std::cout << 7 << std::endl;
    }
    return 0;
}

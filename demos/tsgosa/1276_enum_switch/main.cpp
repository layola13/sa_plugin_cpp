#include <iostream>

enum Color { R, G, B };

int pick(Color c) {
    switch (c) {
        case R:
            return 1;
        case G:
            return 2;
        default:
            return 3;
    }
    return 3;
}

int main() {
    std::cout << pick(R) << std::endl;
    std::cout << pick(B) << std::endl;
    return 0;
}

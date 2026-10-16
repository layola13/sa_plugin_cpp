#include <iostream>

enum E { A = 1, B = 2 };

int main() {
    const E e = B;
    switch (e) {
        case A: std::cout << 1 << std::endl; break;
        case B: std::cout << 2 << std::endl; break;
        default: std::cout << 0 << std::endl;
    }
    return 0;
}

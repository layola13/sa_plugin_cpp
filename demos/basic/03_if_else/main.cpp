#include <iostream>

int main() {
    int score = 85;
    if (score >= 90) {
        std::cout << 1 << std::endl;
    } else if (score >= 60) {
        std::cout << 2 << std::endl;
    } else {
        std::cout << 3 << std::endl;
    }
    if (score < 60) {
        std::cout << 4 << std::endl;
    } else {
        std::cout << 5 << std::endl;
    }
    return 0;
}

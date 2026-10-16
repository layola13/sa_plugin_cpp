#include <iostream>

enum Color { RED, GREEN = 5, BLUE };

int main() {
    std::cout << RED << std::endl;
    std::cout << GREEN << std::endl;
    std::cout << BLUE << std::endl;
    Color c = GREEN;
    std::cout << c << std::endl;
    return 0;
}

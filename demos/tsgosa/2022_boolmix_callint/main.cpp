#include <iostream>

int one() { return 1; }

int main() {
    bool f = true;
    std::cout << (f == one()) << std::endl;
    std::cout << (one() != f) << std::endl;
    return 0;
}

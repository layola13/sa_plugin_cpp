#include <iostream>

int id(int x) {
    return x;
}

int main() {
    std::cout << id(1) << std::endl;
    std::cout << id(2) << std::endl;
    return 0;
}

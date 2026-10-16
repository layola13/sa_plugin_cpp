#include <iostream>

namespace M {
int add(int a, int b) {
    return a + b;
}
int getK() {
    return 10;
}
}

int main() {
    std::cout << M::add(3, 4) << std::endl;
    std::cout << M::getK() << std::endl;
    return 0;
}

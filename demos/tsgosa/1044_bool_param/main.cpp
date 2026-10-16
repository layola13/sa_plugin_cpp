#include <iostream>

int neg(bool b) {
    return b ? 0 : 1;
}

int main() {
    std::cout << neg(true) << std::endl;
    std::cout << neg(false) << std::endl;
    return 0;
}

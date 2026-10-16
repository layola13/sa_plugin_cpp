#include <iostream>

int eqn(bool f, int n) {
    int fi = f;
    return fi == n ? 1 : 0;
}

int main() {
    std::cout << eqn(true, 1) << std::endl;
    std::cout << eqn(true, 2) << std::endl;
    std::cout << eqn(false, 0) << std::endl;
    return 0;
}

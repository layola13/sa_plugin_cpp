#include <iostream>

int eq(bool a, bool b) {
    if (a == b) { return 1; }
    return 0;
}

int main() {
    std::cout << eq(true, false) << std::endl;
    std::cout << eq(true, true) << std::endl;
    return 0;
}

#include <iostream>

namespace N {
int getX() {
    return 41;
}
}

int main() {
    std::cout << N::getX() + 1 << std::endl;
    return 0;
}

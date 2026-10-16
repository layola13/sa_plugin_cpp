#include <iostream>

namespace math {
int square(int x) {
    return x * x;
}
}

int main() {
    std::cout << math::square(9) << std::endl;
    return 0;
}

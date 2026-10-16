#include <iostream>

int one() {
    return 1;
}

int two() {
    return one() + one();
}

int main() {
    std::cout << two() << std::endl;
    return 0;
}

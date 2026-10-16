#include <iostream>

template <typename T>
T id(T x) {
    return x;
}

int main() {
    std::cout << id(1) << std::endl;
    return 0;
}

#include <iostream>

int c() {
    return 0;
}

int main() {
    std::cout << (c() ? 10 : 20) << std::endl;
    return 0;
}

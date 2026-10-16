#include <iostream>

bool isOk() { return true; }

int main() {
    bool f = false;
    std::cout << (f == isOk()) << std::endl;
    std::cout << (isOk() == f) << std::endl;
    return 0;
}

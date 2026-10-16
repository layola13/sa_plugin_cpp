#include <iostream>

void f() {
    bool b = true;
    int n = 5;
    int z = 0;
    std::cout << (!b ? 1 : 0) << std::endl;
    std::cout << (!n ? 1 : 0) << std::endl;
    std::cout << (!z ? 1 : 0) << std::endl;
}

int main() {
    f();
    return 0;
}

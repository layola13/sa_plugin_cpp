#include <iostream>

int main() {
    bool f = true;
    bool x = f != 0;
    std::cout << x << std::endl;
    bool g = false;
    int n = 1;
    while (g != n) { g = true; break; }
    std::cout << 1 << std::endl;
    return 0;
}

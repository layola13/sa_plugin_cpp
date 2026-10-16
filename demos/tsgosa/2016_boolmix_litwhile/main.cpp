#include <iostream>

int main() {
    std::cout << (true == 1) << std::endl;
    bool f = false;
    int n = 0;
    while (f == n) { f = true; break; }
    std::cout << 1 << std::endl;
    return 0;
}

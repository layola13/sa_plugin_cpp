#include <iostream>

int main() {
    bool f = true;
    bool t = false;
    while (f == t) { f = true; break; }
    std::cout << 1 << std::endl;
    return 0;
}

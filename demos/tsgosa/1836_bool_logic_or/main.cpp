#include <iostream>

int main() {
    bool f = false;
    bool g = f || true;
    std::cout << (g ? 1 : 0) << std::endl;
    return 0;
}

#include <iostream>

int main() {
    bool f = true;
    bool g = f && true;
    std::cout << (g ? 1 : 0) << std::endl;
    return 0;
}

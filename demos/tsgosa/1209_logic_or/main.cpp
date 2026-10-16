#include <iostream>

int main() {
    int t = 3;
    int f = 0;
    std::cout << (t ? 3 : 4) << std::endl;
    std::cout << (f ? 0 : 4) << std::endl;
    std::cout << (t ? 3 : 0) << std::endl;
    std::cout << (f ? 0 : 0) << std::endl;
    return 0;
}

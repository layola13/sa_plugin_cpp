#include <iostream>

int main() {
    int o = 1;
    int z = 0;
    int a1 = o ? 2 : 0;
    int b1 = z ? 3 : 0;
    int r1 = a1 ? a1 : b1;
    std::cout << r1 << std::endl;
    int a2 = z ? 0 : 0;
    int r2 = a2 ? 5 : 0;
    std::cout << r2 << std::endl;
    return 0;
}

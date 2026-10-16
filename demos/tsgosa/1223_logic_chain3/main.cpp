#include <iostream>

int main() {
    int o = 1;
    int z = 0;
    int t1 = o ? 2 : 0;
    int r1 = t1 ? 3 : 0;
    std::cout << r1 << std::endl;
    int t2 = o ? 0 : 0;
    int r2 = t2 ? 3 : 0;
    std::cout << r2 << std::endl;
    int t3 = z ? 0 : 0;
    int r3 = t3 ? t3 : 5;
    std::cout << r3 << std::endl;
    return 0;
}

#include <iostream>

int main() {
    int z = 0;
    int o = 1;
    int t1 = z ? 1 : 0;
    int r1 = t1 ? t1 : 2;
    std::cout << r1 << std::endl;
    int t2 = z ? 0 : 0;
    int r2 = o ? 1 : t2;
    std::cout << r2 << std::endl;
    int n = z ? 1 : 0;
    std::cout << !n << std::endl;
    return 0;
}

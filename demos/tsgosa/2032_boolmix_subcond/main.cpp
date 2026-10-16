#include <iostream>

int main() {
    int a[3] = {7, 8, 9};
    bool f = true;
    int i = 2;
    int v = a[i];
    int fi = f;
    int r1 = (v == fi) ? 1 : 0;
    std::cout << r1 << std::endl;
    int w = a[0];
    int r2 = (fi != w) ? 1 : 0;
    std::cout << r2 << std::endl;
    return 0;
}

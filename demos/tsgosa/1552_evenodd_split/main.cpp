#include <iostream>
int main() {
    int a[6] = {1, 2, 3, 4, 5, 6};
    int e = 0;
    int o = 0;
    for (int k = 0; k < 6; k = k + 1) {
        int v = a[k];
        if (v % 2 == 0) { e = e + v; } else { o = o + v; }
    }
    std::cout << e << std::endl;
    std::cout << o << std::endl;
    return 0;
}

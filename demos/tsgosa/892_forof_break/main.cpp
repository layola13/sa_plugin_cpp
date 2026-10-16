#include <iostream>

int main() {
    int a[5] = {1, 2, 3, 4, 5};
    int t = 0;
    for (int i = 0; i < 5; i++) {
        int v = a[i];
        if (v == 3) { break; }
        t += v;
    }
    std::cout << t << std::endl;
    return 0;
}

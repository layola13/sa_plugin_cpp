#include <iostream>

int min3(int a, int b, int c) {
    int m = a;
    if (b < m) {
        m = b;
    }
    if (c < m) {
        m = c;
    }
    return m;
}

int main() {
    std::cout << min3(3, 1, 2) << std::endl;
    return 0;
}

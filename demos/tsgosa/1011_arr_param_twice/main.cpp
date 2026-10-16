#include <iostream>

int sum(int* a, int n) {
    int t = 0;
    for (int i = 0; i < n; i++) {
        t += a[i];
    }
    return t;
}

int main() {
    int a[2] = {1, 2};
    int b[3] = {3, 4, 5};
    std::cout << sum(a, 2) << std::endl;
    std::cout << sum(b, 3) << std::endl;
    return 0;
}

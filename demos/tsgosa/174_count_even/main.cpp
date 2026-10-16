#include <iostream>

int main() {
    int a[8] = {1, 2, 3, 4, 5, 6, 7, 8};
    int n = 0;
    for (int i = 0; i < 8; i++) {
        if (a[i] % 2 == 0) {
            n = n + 1;
        }
    }
    std::cout << n << std::endl;
    return 0;
}

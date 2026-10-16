#include <iostream>

int main() {
    int a[5] = {8, 3, 11, 2, 9};
    int m = a[0];
    for (int i = 1; i < 5; i++) {
        if (a[i] < m) {
            m = a[i];
        }
    }
    std::cout << m << std::endl;
    return 0;
}

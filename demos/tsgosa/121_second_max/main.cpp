#include <iostream>

int main() {
    int a[6] = {5, 1, 9, 3, 9, 2};
    int m1 = a[0];
    int m2 = a[0];
    for (int i = 1; i < 6; i++) {
        if (a[i] > m1) {
            m2 = m1;
            m1 = a[i];
        } else if (a[i] > m2) {
            m2 = a[i];
        }
    }
    std::cout << m1 << " " << m2 << std::endl;
    return 0;
}

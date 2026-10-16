#include <iostream>

int main() {
    int a[5] = {1, 2, 3, 4, 5};
    int k = 2;
    int b[5];
    for (int i = 0; i < 5; i++) {
        b[i] = a[(i + k) % 5];
    }
    std::cout << b[0] << " " << b[1] << " " << b[4] << std::endl;
    return 0;
}

#include <iostream>

int main() {
    int a[3] = {1, 2, 3};
    int b[3] = {4, 5, 6};
    int t = 0;
    for (int i = 0; i < 3; i++) {
        t = t + a[i] * b[i];
    }
    std::cout << t << std::endl;
    return 0;
}

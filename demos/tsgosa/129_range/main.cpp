#include <iostream>

int main() {
    int a[5] = {10, 20, 30, 40, 50};
    int t = 0;
    for (int i = 1; i < 4; i++) {
        t = t + a[i];
    }
    std::cout << t << std::endl;
    return 0;
}

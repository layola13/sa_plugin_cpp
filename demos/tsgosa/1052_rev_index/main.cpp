#include <iostream>

int main() {
    int a[3] = {1, 2, 3};
    int t = 0;
    for (int i = 2; i >= 0; i--) {
        t += a[i];
    }
    std::cout << t << std::endl;
    return 0;
}

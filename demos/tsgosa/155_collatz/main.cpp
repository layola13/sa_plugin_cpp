#include <iostream>

int main() {
    int x = 27;
    int n = 0;
    while (x != 1) {
        if (x % 2 == 0) {
            x = x / 2;
        } else {
            x = 3 * x + 1;
        }
        n = n + 1;
    }
    std::cout << n << std::endl;
    return 0;
}

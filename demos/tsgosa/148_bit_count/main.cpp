#include <iostream>

int main() {
    int x = 29;
    int n = 0;
    while (x != 0) {
        n = n + (x & 1);
        x = x >> 1;
    }
    std::cout << n << std::endl;
    return 0;
}

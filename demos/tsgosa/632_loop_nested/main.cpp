#include <iostream>

int main() {
    int n = 0;
    while (n < 2) {
        for (int i = 0; i < 2; i = i + 1) {
            std::cout << n * 10 + i << std::endl;
        }
        n = n + 1;
    }
    return 0;
}

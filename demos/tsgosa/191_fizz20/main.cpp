#include <iostream>

int main() {
    int n = 0;
    for (int i = 1; i <= 20; i++) {
        if (i % 3 == 0 || i % 5 == 0) {
            n = n + 1;
        }
    }
    std::cout << n << std::endl;
    return 0;
}

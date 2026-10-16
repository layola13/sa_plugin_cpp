#include <iostream>

int main() {
    int n = 0;
    for (; n < 2;) {
        std::cout << n + 20 << std::endl;
        n = n + 1;
    }
    return 0;
}

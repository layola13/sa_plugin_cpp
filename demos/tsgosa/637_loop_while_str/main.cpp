#include <iostream>

int main() {
    const char* s = "hi";
    int n = 3;
    while (n) {
        std::cout << n << std::endl;
        n = n - 1;
    }
    std::cout << 2 << std::endl;
    return 0;
}

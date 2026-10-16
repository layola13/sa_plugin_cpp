#include <iostream>

int main() {
    int n = 0;
    while (n < 2) {
        const char* q = "x";
        std::cout << q << std::endl;
        n = n + 1;
    }
    return 0;
}

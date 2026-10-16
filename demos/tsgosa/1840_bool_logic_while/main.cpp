#include <iostream>

int main() {
    int n = 0;
    bool f = true;
    while (f && n < 3) {
        n = n + 1;
    }
    std::cout << n << std::endl;
    return 0;
}

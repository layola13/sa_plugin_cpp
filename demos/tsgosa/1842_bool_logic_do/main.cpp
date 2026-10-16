#include <iostream>

int main() {
    bool f = true;
    int n = 1;
    do {
        n = n + 1;
    } while (f && n < 3);
    std::cout << n << std::endl;
    return 0;
}

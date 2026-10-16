#include <iostream>

int main() {
    int n = 0;
    bool f = true;
    if (f && true) {
        n = 42;
    }
    std::cout << n << std::endl;
    return 0;
}

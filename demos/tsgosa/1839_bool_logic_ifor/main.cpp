#include <iostream>

int main() {
    int n = 0;
    bool f = false;
    bool g = true;
    if (f || g) {
        n = 7;
    }
    std::cout << n << std::endl;
    return 0;
}

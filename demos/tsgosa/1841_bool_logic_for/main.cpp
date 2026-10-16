#include <iostream>

int main() {
    int n = 0;
    bool f = true;
    bool g = false;
    for (int i = 0; f && i < 2; i = i + 1) {
        n = n + 10;
    }
    std::cout << n << std::endl;
    return 0;
}

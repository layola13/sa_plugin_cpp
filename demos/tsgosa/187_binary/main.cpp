#include <iostream>

int main() {
    int x = 0;
    for (int i = 0; i < 8; i++) {
        x = x * 2 + (i % 2);
    }
    std::cout << x << std::endl;
    return 0;
}

#include <iostream>

int main() {
    int x = 1;
    for (int i = 0; i < 4; i++) { x = x << 1; }
    std::cout << x << std::endl;
    return 0;
}

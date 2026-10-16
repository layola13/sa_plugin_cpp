#include <iostream>
int main() {
    int x = 0;
    for (int i = 0; i < 5; i = i + 1) { x = x + 2 * i; }
    std::cout << x << std::endl;
    return 0;
}

#include <iostream>

int min(int a, int b) { return a < b ? a : b; }
int max(int a, int b) { return a > b ? a : b; }

int main() {
    std::cout << min(3, 7) + max(3, 7) << std::endl;
    return 0;
}

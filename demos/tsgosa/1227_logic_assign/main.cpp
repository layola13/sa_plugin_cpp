#include <iostream>

int main() {
    int x = 0;
    int t = 2;
    int f = 0;
    x = t ? 3 : 0;
    std::cout << x << std::endl;
    x = f ? 0 : 9;
    std::cout << x << std::endl;
    return 0;
}

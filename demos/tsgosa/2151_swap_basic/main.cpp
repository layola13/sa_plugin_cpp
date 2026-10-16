#include <iostream>

int main() {
    int a = 1;
    int b = 2;
    int t = a; a = b; b = t;
    std::cout << a << std::endl;
    std::cout << b << std::endl;
    return 0;
}

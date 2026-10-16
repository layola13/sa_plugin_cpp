#include <iostream>

int main() {
    int a = 1;
    int b = 2;
    int c = 3;
    int na = c + 10;
    int nb = b + 10;
    int nc = a + 10;
    a = na; b = nb; c = nc;
    std::cout << a << std::endl;
    std::cout << b << std::endl;
    std::cout << c << std::endl;
    return 0;
}

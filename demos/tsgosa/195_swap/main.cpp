#include <iostream>

int main() {
    int a = 3;
    int b = 7;
    int t = a;
    a = b;
    b = t;
    std::cout << a << " " << b << std::endl;
    return 0;
}

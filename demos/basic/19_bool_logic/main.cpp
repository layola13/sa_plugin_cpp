#include <iostream>

int main() {
    int a = 1;
    int b = 0;
    std::cout << (a && b) << std::endl;
    std::cout << (a || b) << std::endl;
    std::cout << !a << std::endl;
    std::cout << !b << std::endl;
    bool flag = a == 1 && b == 0;
    std::cout << flag << std::endl;
    return 0;
}

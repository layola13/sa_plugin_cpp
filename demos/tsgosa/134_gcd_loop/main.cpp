#include <iostream>

int main() {
    int a = 48;
    int b = 18;
    while (b != 0) {
        int t = a % b;
        a = b;
        b = t;
    }
    std::cout << a << std::endl;
    return 0;
}

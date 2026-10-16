#include <iostream>

struct Pair {
    int a;
    double b;
};

int main() {
    std::cout << sizeof(int) << std::endl;
    std::cout << sizeof(double) << std::endl;
    std::cout << sizeof(Pair) << std::endl;
    return 0;
}

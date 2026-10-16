#include <iostream>

int add(int a, int b) { return a + b; }
double add(double a, double b) { return a + b; }
int add(int a, int b, int c) { return a + b + c; }

int main() {
    int x = add(1, 2);
    double y = add(2.5, 2.5);
    int z = add(1, 2, 3);
    if (y > 4.0) {
        std::cout << x << std::endl;
    }
    std::cout << z << std::endl;
    return 0;
}

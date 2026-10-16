#include <iostream>

int main() {
    double x = 1.5;
    double y = 2.5;
    double z = x + y * 2.0;
    std::cout << (z > 6.0) << std::endl;
    std::cout << (z < 6.0) << std::endl;
    int whole = (int)z;
    std::cout << whole << std::endl;
    return 0;
}

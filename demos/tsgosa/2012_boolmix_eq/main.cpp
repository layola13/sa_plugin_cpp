#include <iostream>

int main() {
    bool f = true;
    int fi = f;
    std::cout << (fi == 1) << std::endl;
    std::cout << (fi == 0) << std::endl;
    std::cout << (fi == 2) << std::endl;
    return 0;
}

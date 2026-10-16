#include <iostream>

int main() {
    std::cout << (!!5 ? 1 : 0) << std::endl;
    std::cout << (!!0 ? 1 : 0) << std::endl;
    return 0;
}

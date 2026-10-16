#include <iostream>

int main() {
    int M[4] = {-1, 2, true, false};
    std::cout << M[0] << std::endl;
    std::cout << M[1] << std::endl;
    std::cout << M[2] + M[3] << std::endl;
    return 0;
}

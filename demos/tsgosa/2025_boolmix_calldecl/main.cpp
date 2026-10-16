#include <iostream>

int getN() { return 1; }

int main() {
    bool f = true;
    bool x = f == getN();
    std::cout << x << std::endl;
    return 0;
}

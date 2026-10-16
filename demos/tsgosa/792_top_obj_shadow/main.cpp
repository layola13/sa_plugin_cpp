#include <iostream>

struct P {
    int x;
};

int f() {
    P O = {9};
    return O.x;
}

int main() {
    P O = {1};
    std::cout << f() << std::endl;
    std::cout << O.x << std::endl;
    return 0;
}

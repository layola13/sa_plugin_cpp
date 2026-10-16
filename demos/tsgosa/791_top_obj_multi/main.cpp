#include <iostream>

struct P {
    int x;
    int y;
};

int main() {
    P A = {1, 2};
    P B = {3, 4};
    std::cout << A.x + B.y << std::endl;
    return 0;
}

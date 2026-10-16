#include <iostream>

struct P {
    int x;
    int y;
};

int main() {
    P O = {6, 7};
    std::cout << O.x + O.y << std::endl;
    return 0;
}

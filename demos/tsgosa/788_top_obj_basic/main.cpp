#include <iostream>

struct P {
    int x;
    int y;
};

int f(P o) {
    return o.x * 10 + o.y;
}

int main() {
    P O = {1, 2};
    std::cout << f(O) << std::endl;
    std::cout << O.x + O.y << std::endl;
    return 0;
}

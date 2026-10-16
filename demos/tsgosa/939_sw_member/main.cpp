#include <iostream>

struct P {
    int v;
};

int main() {
    P o = {2};
    switch (o.v) {
        case 1: std::cout << 1 << std::endl; break;
        case 2: std::cout << 2 << std::endl; break;
        default: std::cout << 0 << std::endl;
    }
    return 0;
}

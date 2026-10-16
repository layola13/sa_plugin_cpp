#include <iostream>

struct P {
    int x;
};

int get(P p) {
    return p.x;
}

int main() {
    P o = {5};
    std::cout << get(o) << std::endl;
    return 0;
}

#include <iostream>

class Box {
    int w;
    int h;
public:
    Box() {
        w = 2;
        h = 3;
    }
    int area() { return w * h; }
};

int main() {
    Box b;
    std::cout << b.area() << std::endl;
    return 0;
}

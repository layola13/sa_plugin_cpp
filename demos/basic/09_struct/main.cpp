#include <iostream>

struct Point {
    int x;
    int y;
};

int main() {
    Point p{3, 4};
    std::cout << p.x << std::endl;
    std::cout << p.y << std::endl;
    p.x = 10;
    std::cout << p.x + p.y << std::endl;
    return 0;
}

#include <iostream>
struct Pt { int x; int y; };
int main() {
    Pt p;
    p.x = 3;
    p.y = 4;
    std::cout << p.x * p.x + p.y * p.y << std::endl;
    return 0;
}

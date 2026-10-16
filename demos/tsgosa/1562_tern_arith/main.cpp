#include <iostream>
int main() {
    int x = 9;
    int y = x > 5 ? x - 5 : x + 5;
    std::cout << y << std::endl;
    return 0;
}

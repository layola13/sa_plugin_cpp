#include <iostream>

int pick(int a, int b) {
    if (a > b) {
        return a;
    }
    return b;
}

int main() {
    std::cout << pick(7, 12) << " " << pick(9, 3) << std::endl;
    return 0;
}

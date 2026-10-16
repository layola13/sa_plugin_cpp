#include <iostream>

int sign(int x) {
    if (x > 0) {
        if (x > 100) {
            return 2;
        }
        return 1;
    } else if (x < 0) {
        return -1;
    }
    return 0;
}

int main() {
    std::cout << sign(200) << " " << sign(5) << " " << sign(-3) << " " << sign(0) << std::endl;
    return 0;
}

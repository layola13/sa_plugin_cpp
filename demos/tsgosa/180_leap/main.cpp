#include <iostream>

int isLeap(int y) {
    if (y % 400 == 0) {
        return 1;
    }
    if (y % 100 == 0) {
        return 0;
    }
    if (y % 4 == 0) {
        return 1;
    }
    return 0;
}

int main() {
    std::cout << isLeap(2000) << " " << isLeap(1900) << " " << isLeap(2024) << std::endl;
    return 0;
}

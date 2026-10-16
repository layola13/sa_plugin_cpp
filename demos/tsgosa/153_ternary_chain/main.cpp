#include <iostream>

int grade(int s) {
    int g = s >= 90 ? 1 : s >= 60 ? 2 : 3;
    return g;
}

int main() {
    std::cout << grade(95) << " " << grade(70) << " " << grade(30) << std::endl;
    return 0;
}

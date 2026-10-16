#include <iostream>

int grade(int s) {
    int lo = s >= 60 ? 2 : 3;
    return s >= 90 ? 1 : lo;
}

int main() {
    std::cout << grade(95) << std::endl;
    std::cout << grade(70) << std::endl;
    std::cout << grade(30) << std::endl;
    return 0;
}

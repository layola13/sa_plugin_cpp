#include <iostream>

int main() {
    int t = 0;
    for (int i = 0; i < 5 && t < 100; i++) { t += i; }
    std::cout << t << std::endl;
    return 0;
}

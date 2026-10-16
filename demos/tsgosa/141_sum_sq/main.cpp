#include <iostream>

int main() {
    int t = 0;
    for (int i = 1; i <= 5; i++) {
        t = t + i * i;
    }
    std::cout << t << std::endl;
    return 0;
}

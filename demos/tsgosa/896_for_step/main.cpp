#include <iostream>

int main() {
    int t = 0;
    for (int i = 0; i < 10; i += 2) { t += i; }
    std::cout << t << std::endl;
    return 0;
}

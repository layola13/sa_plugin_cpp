#include <iostream>

int main() {
    int i = 0;
    int t = 0;
    do {
        t = t + i;
        i = i + 1;
    } while (i < 5);
    std::cout << t << std::endl;
    return 0;
}

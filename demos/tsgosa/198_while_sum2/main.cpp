#include <iostream>

int main() {
    int i = 10;
    int t = 0;
    while (i > 0) {
        t = t + i;
        i = i - 1;
    }
    std::cout << t << std::endl;
    return 0;
}

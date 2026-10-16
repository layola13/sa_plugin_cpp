#include <iostream>

int main() {
    int i = 5;
    int t = 0;
    while (i > 0) {
        t += i;
        i -= 2;
    }
    std::cout << t << std::endl;
    return 0;
}

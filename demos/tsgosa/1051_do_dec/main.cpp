#include <iostream>

int main() {
    int i = 4;
    int t = 0;
    do {
        t += i;
        i -= 1;
    } while (i > 0);
    std::cout << t << std::endl;
    return 0;
}

#include <iostream>

int main() {
    int i = 0;
    int t = 0;
    do {
        i += 1;
        if (i % 2 == 0) {
            continue;
        }
        t += i;
    } while (i < 6);
    std::cout << t << std::endl;
    return 0;
}

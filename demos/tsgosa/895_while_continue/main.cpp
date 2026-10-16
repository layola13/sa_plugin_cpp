#include <iostream>

int main() {
    int i = 0;
    int t = 0;
    while (i < 10) {
        i += 1;
        if (i % 3 == 0) { continue; }
        t += i;
    }
    std::cout << t << std::endl;
    return 0;
}

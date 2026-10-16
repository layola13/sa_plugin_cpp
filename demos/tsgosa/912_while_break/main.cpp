#include <iostream>

int main() {
    int i = 0;
    int t = 0;
    while (true) {
        i += 1;
        if (i > 5) { break; }
        t += i;
    }
    std::cout << t << std::endl;
    return 0;
}

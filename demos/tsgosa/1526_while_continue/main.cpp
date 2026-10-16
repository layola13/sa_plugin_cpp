#include <iostream>
int main() {
    int t = 0;
    int i = 0;
    while (i < 6) {
        i = i + 1;
        if (i % 2 == 0) { continue; }
        t = t + i;
    }
    std::cout << t << std::endl;
    return 0;
}

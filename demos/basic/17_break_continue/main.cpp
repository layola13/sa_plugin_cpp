#include <iostream>

int main() {
    int total = 0;
    for (int i = 1; i <= 30; i++) {
        if (i % 3 == 0) {
            continue;
        }
        if (total + i > 20) {
            break;
        }
        total += i;
    }
    std::cout << total << std::endl;
    return 0;
}

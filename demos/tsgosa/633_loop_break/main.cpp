#include <iostream>

int main() {
    for (int i = 0; i < 5; i = i + 1) {
        if (i == 1) {
            continue;
        }
        if (i == 3) {
            break;
        }
        std::cout << i << std::endl;
    }
    return 0;
}

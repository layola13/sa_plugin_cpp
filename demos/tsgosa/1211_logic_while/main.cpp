#include <iostream>

int main() {
    int i = 3;
    while (i && i < 10) {
        i += 4;
        if (i > 5) { break; }
    }
    std::cout << i << std::endl;
    return 0;
}

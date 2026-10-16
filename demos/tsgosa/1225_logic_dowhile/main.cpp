#include <iostream>

int main() {
    int i = 0;
    do {
        i += 1;
    } while (i < 3 && i > 0);
    std::cout << i << std::endl;
    return 0;
}

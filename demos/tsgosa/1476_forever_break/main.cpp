#include <iostream>
int main() {
    int i = 0;
    for (;;) {
        i = i + 1;
        if (i >= 3) { break; }
    }
    std::cout << i << std::endl;
    return 0;
}

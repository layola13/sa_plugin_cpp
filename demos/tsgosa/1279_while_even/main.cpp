#include <iostream>

int main() {
    int s = 0;
    int i = 0;
    while (i < 8) {
        i = i + 2;
        s = s + i;
    }
    std::cout << s << std::endl;
    return 0;
}

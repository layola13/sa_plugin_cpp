#include <iostream>

int main() {
    int s = 0;
    int i = 0;
    do {
        s = s + i;
        i = i + 1;
    } while (i < 5);
    std::cout << s << std::endl;
    return 0;
}

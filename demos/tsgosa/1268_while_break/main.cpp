#include <iostream>

int main() {
    int s = 0;
    int i = 0;
    while (i < 10) {
        i = i + 1;
        if (i == 4) {
            continue;
        }
        if (i == 7) {
            break;
        }
        s = s + i;
    }
    std::cout << s << std::endl;
    return 0;
}

#include <iostream>
int main() {
    int s = 0;
    for (int i = 0; i < 10; i = i + 1) {
        if (i >= 3) { break; }
        s = s + i;
    }
    std::cout << s << std::endl;
    return 0;
}

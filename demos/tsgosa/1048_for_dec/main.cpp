#include <iostream>

int main() {
    int t = 0;
    for (int i = 10; i > 0; i -= 3) {
        t += i;
    }
    std::cout << t << std::endl;
    return 0;
}

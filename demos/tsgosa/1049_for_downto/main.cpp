#include <iostream>

int main() {
    int t = 0;
    for (int i = 5; i >= 0; i--) {
        t += i;
    }
    std::cout << t << std::endl;
    return 0;
}

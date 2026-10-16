#include <iostream>

int n() {
    return 4;
}

int main() {
    int t = 0;
    for (int i = 0; i < n(); i++) {
        t += i;
    }
    std::cout << t << std::endl;
    return 0;
}

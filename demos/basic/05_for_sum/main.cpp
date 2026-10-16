#include <iostream>

int main() {
    int total = 0;
    for (int i = 1; i <= 10; i++) {
        total += i * i;
    }
    std::cout << total << std::endl;
    return 0;
}

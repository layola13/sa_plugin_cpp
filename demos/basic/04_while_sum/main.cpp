#include <iostream>

int main() {
    int total = 0;
    int i = 1;
    while (i <= 100) {
        total += i;
        i++;
    }
    std::cout << total << std::endl;
    return 0;
}

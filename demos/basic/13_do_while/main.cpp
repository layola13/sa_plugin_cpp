#include <iostream>

int main() {
    int i = 0;
    int total = 0;
    do {
        total += i;
        i++;
    } while (i < 5);
    std::cout << total << std::endl;
    return 0;
}

#include <iostream>

int main() {
    int data[5] = {3, 1, 4, 1, 5};
    std::cout << data[0] << std::endl;
    std::cout << data[4] << std::endl;
    data[1] = 9;
    int total = 0;
    for (int i = 0; i < 5; i++) {
        total += data[i];
    }
    std::cout << total << std::endl;
    return 0;
}

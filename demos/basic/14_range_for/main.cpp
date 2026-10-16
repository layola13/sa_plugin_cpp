#include <iostream>

int main() {
    int data[4] = {2, 4, 6, 8};
    int total = 0;
    for (int v : data) {
        total += v;
    }
    std::cout << total << std::endl;
    return 0;
}

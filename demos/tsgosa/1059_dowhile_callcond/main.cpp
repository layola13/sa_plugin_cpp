#include <iostream>

int n() {
    return 2;
}

int main() {
    int i = 0;
    do {
        i += 1;
    } while (i < n());
    std::cout << i << std::endl;
    return 0;
}

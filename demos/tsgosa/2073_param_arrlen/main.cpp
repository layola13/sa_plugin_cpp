#include <iostream>

int len(int* a, int n) {
    return n;
}

int main() {
    int t[3] = {7, 8, 9};
    std::cout << len(t, 3) << std::endl;
    return 0;
}

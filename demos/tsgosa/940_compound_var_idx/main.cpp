#include <iostream>

int main() {
    int a[3] = {1, 2, 3};
    const int k = 2;
    a[k] += 10;
    std::cout << a[2] << std::endl;
    return 0;
}

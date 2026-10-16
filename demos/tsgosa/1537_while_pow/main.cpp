#include <iostream>
int main() {
    int n = 2;
    int p = 1;
    while (n > 0) { p = p * 10; n = n - 1; }
    std::cout << p << std::endl;
    return 0;
}

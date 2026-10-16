#include <iostream>

int main() {
    int a[2] = {9, 8};
    int s = 0;
    for (int i = 0; i < 2; i++) { s = s + a[i]; }
    std::cout << s << std::endl;
    return 0;
}

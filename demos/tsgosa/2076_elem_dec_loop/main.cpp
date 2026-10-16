#include <iostream>

int main() {
    int a[1] = {5};
    a[0]--;
    std::cout << a[0] << std::endl;
    int s = 0;
    for (int i = 0; i < 3; i = i + 1) { s = s + a[0]; }
    std::cout << s << std::endl;
    return 0;
}

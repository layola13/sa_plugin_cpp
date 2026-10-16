#include <iostream>

int main() {
    int a[3] = {7, 8, 9};
    bool f = true;
    int fi = f;
    int i = 2;
    bool x = fi == a[i];
    std::cout << x << std::endl;
    return 0;
}

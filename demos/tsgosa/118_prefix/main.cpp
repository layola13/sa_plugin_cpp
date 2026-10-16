#include <iostream>

int main() {
    int a[3] = {2, 4, 6};
    int t = 0;
    for (int i = 0; i < 3; i++) {
        t = t + a[i];
        a[i] = t;
    }
    std::cout << a[0] << " " << a[1] << " " << a[2] << std::endl;
    return 0;
}

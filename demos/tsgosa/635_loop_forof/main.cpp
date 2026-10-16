#include <iostream>

void f() {
    int a[2] = {1, 2};
    for (int i = 0; i < 2; i = i + 1) {
        std::cout << a[i] + 100 << std::endl;
    }
}

int main() {
    f();
    return 0;
}

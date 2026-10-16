#include <iostream>

int eq0(int* a, int n, bool f) {
    int fi = f;
    return fi == a[0] ? 1 : 0;
}

int main() {
    int t[1] = {5};
    std::cout << eq0(t, 1, true) << std::endl;
    return 0;
}

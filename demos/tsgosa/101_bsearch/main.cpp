#include <iostream>

int bsearch(int* a, int n, int key) {
    for (int i = 0; i < n; i++) {
        if (a[i] == key) {
            return i;
        }
    }
    return -1;
}

int main() {
    int a[5] = {1, 3, 5, 7, 9};
    std::cout << bsearch(a, 5, 5) << " " << bsearch(a, 5, 4) << std::endl;
    return 0;
}

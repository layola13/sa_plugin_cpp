#include <iostream>

int main() {
    int a[3] = {1, 3, 5};
    int b[3] = {2, 4, 6};
    int c[6];
    int i = 0;
    int j = 0;
    int k = 0;
    while (i < 3 && j < 3) {
        if (a[i] < b[j]) {
            c[k] = a[i];
            k = k + 1;
            i = i + 1;
        } else {
            c[k] = b[j];
            k = k + 1;
            j = j + 1;
        }
    }
    while (i < 3) {
        c[k] = a[i];
        k = k + 1;
        i = i + 1;
    }
    while (j < 3) {
        c[k] = b[j];
        k = k + 1;
        j = j + 1;
    }
    std::cout << k << " " << c[0] << " " << c[5] << std::endl;
    return 0;
}

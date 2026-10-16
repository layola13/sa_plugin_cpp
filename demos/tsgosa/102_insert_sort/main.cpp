#include <iostream>

int main() {
    int a[5] = {5, 2, 4, 1, 3};
    for (int i = 1; i < 5; i++) {
        int k = a[i];
        int j = i - 1;
        while (j >= 0) {
            if (a[j] > k) {
                a[j + 1] = a[j];
                j = j - 1;
            } else {
                break;
            }
        }
        a[j + 1] = k;
    }
    std::cout << a[0] << " " << a[1] << " " << a[2] << " " << a[3] << " " << a[4] << std::endl;
    return 0;
}

#include <iostream>

int main() {
    int a[6] = {1, 3, 2, 3, 1, 3};
    int best = a[0];
    int bestN = 0;
    for (int i = 0; i < 6; i++) {
        int n = 0;
        for (int j = 0; j < 6; j++) {
            if (a[j] == a[i]) {
                n = n + 1;
            }
        }
        if (n > bestN) {
            bestN = n;
            best = a[i];
        }
    }
    std::cout << best << " " << bestN << std::endl;
    return 0;
}

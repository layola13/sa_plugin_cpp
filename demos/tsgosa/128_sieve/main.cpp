#include <iostream>

int main() {
    int n = 20;
    int isP[20];
    for (int i = 0; i < n; i++) {
        isP[i] = 1;
    }
    for (int i = 2; i < n; i++) {
        if (isP[i] == 1) {
            for (int j = i + i; j < n; j = j + i) {
                isP[j] = 0;
            }
        }
    }
    int c = 0;
    for (int i = 2; i < n; i++) {
        c = c + isP[i];
    }
    std::cout << c << " " << isP[17] << std::endl;
    return 0;
}

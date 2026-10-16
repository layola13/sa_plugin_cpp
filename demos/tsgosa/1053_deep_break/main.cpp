#include <iostream>

int main() {
    int t = 0;
    for (int i = 0; i < 5; i++) {
        for (int j = 0; j < 5; j++) {
            for (int k = 0; k < 5; k++) {
                if (k == 2) {
                    break;
                }
                t += 1;
            }
            if (j == 3) {
                break;
            }
        }
    }
    std::cout << t << std::endl;
    return 0;
}

#include <iostream>

int main() {
    int t = 0;
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            if ((i + j) % 2 == 0) { continue; }
            t += 1;
        }
    }
    std::cout << t << std::endl;
    return 0;
}

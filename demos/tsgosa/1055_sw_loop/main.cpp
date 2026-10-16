#include <iostream>

int main() {
    int t = 0;
    for (int i = 0; i < 4; i++) {
        switch (i % 2) {
            case 0:
                t += 10;
                break;
            default:
                t += 1;
        }
    }
    std::cout << t << std::endl;
    return 0;
}

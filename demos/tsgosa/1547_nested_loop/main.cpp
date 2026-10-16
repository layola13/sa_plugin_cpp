#include <iostream>
int main() {
    int found = -1;
    for (int i = 0; i < 3; i = i + 1) {
        for (int j = 0; j < 3; j = j + 1) {
            if (i * 3 + j == 4) { found = i * 3 + j; }
        }
    }
    std::cout << found << std::endl;
    return 0;
}

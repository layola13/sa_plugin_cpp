#include <iostream>

int main() {
    int count = 0;
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j <= i; j++) {
            count++;
        }
    }
    std::cout << count << std::endl;
    return 0;
}

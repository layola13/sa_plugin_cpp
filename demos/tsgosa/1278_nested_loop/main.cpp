#include <iostream>

int main() {
    int s = 0;
    for (int i = 0; i < 3; i = i + 1) {
        for (int j = 0; j < 4; j = j + 1) {
            s = s + 1;
        }
    }
    std::cout << s << std::endl;
    return 0;
}

#include <iostream>

int total(int* SCORES, int n) {
    return SCORES[0] + SCORES[1] + SCORES[2] + n;
}

int main() {
    int SCORES[3] = {10, 20, 30};
    std::cout << total(SCORES, 3) << std::endl;
    std::cout << SCORES[1] << std::endl;
    std::cout << 3 << std::endl;
    return 0;
}

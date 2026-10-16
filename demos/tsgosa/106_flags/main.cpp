#include <iostream>

int main() {
    int r = 1;
    int w = 2;
    int x = 4;
    int perm = r | w | x;
    std::cout << (perm & w) << " " << (perm & 8) << " " << (perm ^ w) << std::endl;
    return 0;
}

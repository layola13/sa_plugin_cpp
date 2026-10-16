#include <iostream>
int main() {
    int t = 1;
    for (int i = 1; i <= 4; i = i + 1) { t = t * i; }
    std::cout << t << std::endl;
    return 0;
}

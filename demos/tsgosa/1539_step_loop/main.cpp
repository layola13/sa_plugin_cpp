#include <iostream>
int main() {
    int total = 0;
    for (int i = 10; i > 0; i = i - 2) { total = total + i; }
    std::cout << total << std::endl;
    return 0;
}

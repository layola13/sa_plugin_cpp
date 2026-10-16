#include <iostream>
int main() {
    int sum = 0;
    int a[3] = {5, 10, 15};
    for (int i = 0; i < 3; i = i + 1) { sum = sum + a[i]; }
    std::cout << sum << std::endl;
    return 0;
}

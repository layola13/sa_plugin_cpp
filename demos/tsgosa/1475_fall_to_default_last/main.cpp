#include <iostream>
int main() {
    int n = 2;
    int s = 0;
    switch (n) {
        case 1:
            s = s + 1;
            break;
        case 2:
            s = s + 10;
        default:
            s = s + 100;
    }
    std::cout << s << std::endl;
    return 0;
}

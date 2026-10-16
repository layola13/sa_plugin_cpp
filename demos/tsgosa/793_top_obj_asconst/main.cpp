#include <iostream>

struct P {
    int x;
};

int main() {
    const P O = {9};
    std::cout << O.x << std::endl;
    return 0;
}

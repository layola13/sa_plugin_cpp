#include <iostream>

struct P {
    int x;
};

struct Q {
    const char* name;
    int n;
};

int main() {
    P O = {1};
    Q W = {"hi", 0};
    std::cout << O.x << std::endl;
    std::cout << W.name << std::endl;
    std::cout << W.n << std::endl;
    return 0;
}

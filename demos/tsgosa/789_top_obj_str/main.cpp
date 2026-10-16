#include <iostream>

struct Q {
    const char* name;
    int n;
};

int main() {
    Q O = {"ab", 5};
    std::cout << O.name << std::endl;
    std::cout << O.n << std::endl;
    return 0;
}

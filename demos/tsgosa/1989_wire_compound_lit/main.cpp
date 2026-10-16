#include <iostream>

class C {
public:
    int n;
    C() {
        n = 5;
        this.n += 1;
    }
};

int main() {
    C c;
    std::cout << c.n << std::endl;
    return 0;
}

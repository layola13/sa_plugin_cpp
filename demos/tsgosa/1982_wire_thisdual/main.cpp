#include <iostream>

class C {
public:
    int a;
    int b;
    int n;
    C() {
        a = 3;
        b = 4;
        n = 0;
        this.n = this.a + this.b;
    }
};

int main() {
    C c;
    std::cout << c.n << std::endl;
    return 0;
}

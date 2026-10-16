#include <iostream>
enum E { A = 2, B = 5 };
int cmp(E e) { return e == B ? 1 : 0; }
int main() {
    std::cout << cmp(B) << std::endl;
    std::cout << cmp(A) << std::endl;
    return 0;
}

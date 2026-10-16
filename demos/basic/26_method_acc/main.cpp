#include <iostream>

class Acc {
    int total;
public:
    void add(int x) { total = total + x; }
    int value() { return total; }
};

int sum_to(int n) {
    Acc acc;
    for (int i = 1; i <= n; i++) {
        acc.add(i);
    }
    return acc.value();
}

int main() {
    std::cout << sum_to(10) << std::endl;
    return 0;
}

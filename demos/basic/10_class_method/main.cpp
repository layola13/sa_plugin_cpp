#include <iostream>

class Counter {
    int count;
public:
    void tick() {
        count = count + 1;
    }
    int get() { return count; }
};

int main() {
    Counter c;
    c.tick();
    c.tick();
    c.tick();
    std::cout << c.get() << std::endl;
    return 0;
}

#include <iostream>

struct Point {
    int x;
    int y;
    int sum() { return x + y; }
};

int add(int a, int b) {
    return a + b;
}

int range_sum(int* data, int n) {
    int acc = 0;
    for (int i = 0; i < n; i++) {
        acc += data[i];
    }
    return acc;
}

int main() {
    Point p{3, 4};
    int total = 0;
    for (int i = 0; i < 5; i++) {
        total += add(i, p.sum());
    }
    int data[3] = {10, 20, 30};
    int acc = range_sum(data, 3);
    int doubled = 0;
    for (int v : data) {
        doubled += v * 2;
    }
    std::cout << total << " " << acc << " " << doubled << std::endl;
    return 0;
}

#include <iostream>

enum D { Sun, Mon, Tue, Wed, Thu, Fri, Sat };

int isWeekend(D d) {
    if (d == Sun) {
        return 1;
    }
    if (d == Sat) {
        return 1;
    }
    return 0;
}

int main() {
    std::cout << isWeekend(Sun) << " " << isWeekend(Mon) << " " << isWeekend(Sat) << std::endl;
    return 0;
}

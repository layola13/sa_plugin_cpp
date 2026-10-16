int f(int x) { return x; }
int f(long x) { return 2; }

int main() {
    bool b = true;
    int y = f(b);
    return y;
}

# 27 Overload

- `main.cpp`: free-function overloads `add(int,int)`, `add(double,double)`,
  `add(int,int,int)` resolved by arity then conversion rank; each overload
  owns one mangled SA symbol (`@add__i32_i32`, `@add__f64_f64`, ...).
- `expected.stdout`: exact program output; `main.sa` is the reviewed SA text.

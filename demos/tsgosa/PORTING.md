# tsgosa rule-corpus porting manifest

tsgosa holds ~2215 numbered rule demos (`main.ts` + `expected.stdout`, plus
`expect.refused` for refusal rules). This file tracks what was ported to
C++ (`demos/tsgosa/<orig-name>/`, original numbers kept for traceability),
what was deliberately skipped, and what remains.

Porting rules (fidelity first):
- `expected.stdout` is copied byte-identical; a port only lands when
  `cpp build` + `sa check` + run output all match exactly.
- In-subset rephrases are allowed (e.g. `a.length` → known constant,
  `===` → `==`, array params get an explicit length) and noted per demo.
- Anything needing out-of-subset features is SKIPPED with a reason, never
  adapted into a different rule.

## Wave 1 (done): 77 ported, 5 skipped, 4 refusal demos

Acceptance: 26 basic + 77 tsgosa + 4 neg = 107/107 on js AND exe
backends, plus 17/17 unit tests. Committed `main.sa` files are
coverage-checked in sync by `tools/sweep.sh`.

Ported (all green on js + exe backends):
- logic/arith: 1208_logic_and, 1209_logic_or, 1210_logic_cond,
  1211_logic_while, 1212_logic_mixed, 1213_logic_boollit, 1217_bool_if,
  1220_double_negation, 1221_logic_nesting, 1222_logic_forcond,
  1223_logic_chain3, 1225_logic_dowhile, 1227_logic_assign,
  1216_arith_chain, 1261_ternary_max, 1262_nested_ternary, 1263_clamp,
  1264_minmax_sum, 1267_between
- bit/shift: 1229_bitwise, 1230_divmod_trunc, 1232_shift_compound,
  1233_shift_varcount, 1234_shift_loop, 1235_shift_neg, 1236_shift_mixed,
  1238_compound_bitwise, 1239_shift_chain, 1240_divmod_compound,
  1243_shift_edges, 1244_shift_negative, 1245_shift_arith,
  1247_shift_compare, 1248_bit_condition, 1249_bit_ternary,
  1250_mask_idioms, 1251_xor_swap
- loops/calls: 1048_for_dec, 1049_for_downto, 1050_while_dec, 1051_do_dec,
  1052_rev_index, 1053_deep_break, 1054_do_once, 1055_sw_loop,
  1268_while_break, 1269_dowhile_acc, 1270_for_break, 1278_nested_loop,
  1279_while_even, 1057_for_call_bound, 1060_switch_calldisc,
  1061_tern_callcond, 1062_nested_calls, 1065_chained_returns,
  1066_elseif_calls, 1059_dowhile_callcond
- algorithms/misc: 101_bsearch, 102_insert_sort, 119_gcd3, 120_lcm,
  121_second_max, 122_rotate, 123_merge, 125_fact, 126_clamp, 128_sieve,
  129_range, 116_minloop, 112_pick_max, 1044_bool_param, 1076_const_enum,
  1276_enum_switch, 1028_ns_func, 1008_call_twice, 1011_arr_param_twice,
  1012_fib_twice

Skipped with reason:
- 1038_shortcircuit: needs lambdas + short-circuit elision (v0.1
  evaluates both sides); rephrasing would erase the rule.
- 1228_shift_sign, 1242_int_idioms: depend on `>>>` (logical shift).
- 103_palindrome, 127_sorted: need string data ops / lambdas.

## Not portable by construction (never planned)

- regex/*match*/split/pad/repeat/slice-string suites, Map/Set,
  Date, JSON, Promise/async, closures/callbacks, inheritance/super,
  exceptions/throw/catch (`*_refuse` stays TS-side), templates/generics,
  interfaces/abstract/override, `typeof`/`instanceof`/`in`, getters/setters,
  static blocks, spread/destructure/optional-chaining/nullish, Date,
  2D arrays, String/Array methods, `switch(true)` on non-ints, float
  printing, `console.log(true)` word outputs.

## Pending (later waves)

Everything else under tsgosa/demos not listed above: triage by `main.ts`
content (many numeric/loop ports remain, e.g. the 12xx–18xx arith/loop
families and the 2xxx suites). Negative (`expect.refused`) ports map to
our explicit subset errors; see `demos/tsgosa-neg/` (planned).

## Wave 2 (done): +148 ported (1xx/6xx/14xx-15xx/18xx-19xx/20xx-21xx/7xx-9xx)

- 1xx numeric/loop core (30): 106_flags, 118_prefix, 134_gcd_loop,
  135_pow_loop, 137_tri, 141_sum_sq, 142_dot, 146_mode, 148_bit_count,
  152_enum_calc, 153_ternary_chain, 155_collatz, 158_do_sum,
  159_gcd_sum, 164_num_sep, 169_neg_idx, 173_fib_loop, 174_count_even,
  175_min3, 179_div_mod, 180_leap, 181_gcd_all, 183_prime_upto,
  187_binary, 188_select, 189_nest_if3, 191_fizz20, 195_swap,
  197_and_or, 198_while_sum2 (+889_do_continue, ported post-fix below)
- 6xx top_* rules (16, whole 600-699 range triaged)
- 14xx-15xx (30): switch fallthrough, class statics via ::, enums,
  calls in conditions, POD structs
- 18xx-19xx (11, range fully triaged): bool-logic matrices,
  default-ctor wiring
- 20xx-21xx (30): bool equality mixes, bool call results, array
  params, swap idioms
- 7xx-9xx (30): for..of/break/continue loops, switch variants,
  top-level const/object/array/global entry rephrases, math-as-ternary

Wave-2 porting surfaced two compiler bugs, both fixed and
regression-covered here:
- do-while `continue` skipped the condition (now jumps to a cond label);
- nested ternary left its inner result binding leaking out of scope
  (scalar results now copy out and release at their own merge).
- Bonus: ternary/switch/if conditions now constant-fold (incl. i32
  wraparound), so literal conditions and `case 1+2:` work.

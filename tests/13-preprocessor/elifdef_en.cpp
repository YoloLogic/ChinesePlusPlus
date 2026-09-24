// English directive spelling. The warning must name the relation in CHINESE,
// exactly as the same file written with the Chinese spelling does -- this is
// the directive analogue of `static_assert` still printing `静态断言`.
#define A 1
#if 0
#elifdef A
#endif
int x;

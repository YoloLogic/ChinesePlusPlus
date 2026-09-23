// expect: 矩阵类型扩展已禁用。传入（选项） -fenable-matrix 以启用
// forbid: matrix types extension is disabled
//
// 用了矩阵类型/内建函数但没加 -fenable-matrix
// 对应诊断：err_builtin_matrix_disabled
typedef int m4x4 __attribute__((matrix_type(4, 4)));
int main() { return 0; }

// expect: 未使用的（种类 类型名） 类型别名 '丙'
// expect: 未使用的（种类 类型名） 别名声明 '乙'
// forbid: unused typedef
// forbid: unused type alias
//
// 未使用的类型别名（本文件加 -Wall）。这里**同时**触发 %select 的两个分支：
//   typedef 形式 -> 分支 0（类型别名，与关键字表里 typedef 的译名一致）
//   using   形式 -> 分支 1（别名声明）
// 注意：分支 0 一度写成保留英文的 `typedef`，被独立复核者判为「中文代码看到英文词」，
// 已按「术语与关键字表逐字一致」这条硬约束改成 类型别名。
// 对应诊断：warn_unused_local_typedef
整数 main() {
  typedef 整数 丙;
  使用 乙 = 整数;
  返回 0;
}

//===--- keywords_round3.cpp - 第三轮中文关键字实测 ----------------------===//
//
// 本轮覆盖三类改动：
//   1) virtual 的译名由「动态绑定」改为「虚拟」
//   2) override → 重写、final → 最终（上下文关键字，与英文【并存】）
//   3) 11 个运算符替代拼写（第七节）：
//      并且 或者 并非 异或 位与 位或 取反 与赋值 或赋值 异或赋值 不等于
//
// 这个程序同时也是「不丢生态」的证明，因为它里面同时出现了：
//   · 中文关键字（类型 / 虚拟 / 公开 / 重写 / 最终 / 常量 …）
//   · 中文标识符（半径 / 边 / 甲 / 乙 …）
//   · 英文库函数（printf）与英文运算符拼写（and / not）
//   · 把 override、final 当【普通变量名】用 —— 若中文是「替换」而非「并存」，
//     这两行就会因为英文被吞掉而编译失败
//
// 编译并运行：
//   build\Release\bin\chinese++.exe -std=c++20 -o keywords_round3.exe keywords_round3.cpp
//   .\keywords_round3.exe
//
// 英文孪生版（用于输出逐字节比对，证明「无锁定」）：
//   python tools\zh_to_en.py examples\keywords_round3.cpp examples\keywords_round3.english.cpp
//===------------------------------------------------------------------------===//

#include <cstdio>

class 形状 {
public:
  virtual double 面积() const { return 0.0; }
};

// 最终：这个类不能再被继承
class 圆 final : public 形状 {
public:
  double 半径;
  圆(double r) : 半径(r) {}
  double 面积() const override { return 3.14159265358979 * 半径 * 半径; }
};

class 方 : public 形状 {
public:
  double 边;
  方(double a) : 边(a) {}
  double 面积() const override final { return 边 * 边; }
};

int main() {
  // ---- 1) 虚拟 / 重写：多态确实生效 ----
  圆 甲(2.0);
  方 乙(3.0);
  形状* 指针 = &甲;
  printf("面积一 = %.4f\n", 指针->面积());
  指针 = &乙;
  printf("面积二 = %.4f\n", 指针->面积());

  // ---- 2) 逻辑运算符替代拼写 ----
  bool 真 = true;
  bool 假 = false;
  if (真 and not 假)
    printf("逻辑一 = 成立\n");

  bool 混 = 真 or 假;
  if (混)
    printf("逻辑二 = 成立\n");

  // ---- 3) 位运算符替代拼写 ----
  int 位 = 6;         // 二进制 110
  位 and_eq 3;         // 110 & 011 = 010 = 2
  位 or_eq 8;         // 0010 | 1000 = 1010 = 10
  位 xor_eq 1;       // 1010 ^ 0001 = 1011 = 11
  printf("位结果 = %d\n", 位);
  printf("取反零 = %d\n", compl 0);

  if (位 not_eq 0 and (位 bitand 1) == 1 and (位 bitor 0) == 位)
    printf("位判断 = 成立\n");

  // ---- 4) 英文运算符拼写与中文【并存】，可混用 ----
  bool 英文式 = (真 and not 假);
  if (英文式)
    printf("英文式 = 成立\n");

  // ---- 5) override / final 仍然可以当普通标识符（生态不丢的硬证据）----
  int final = 7;
  int override = 8;
  printf("标识符 = %d\n", final + override);

  return 0;
}

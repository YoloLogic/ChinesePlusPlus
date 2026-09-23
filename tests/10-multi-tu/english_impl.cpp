// 英文关键字实现文件 —— 由 中文实现.cpp 机械转译而来，应产出完全相同的符号
#include "iface.h"
#include <cstdio>

using namespace std;

// ── 自由函数重载 ──
int 求面积(int 边长) { return 边长 * 边长; }
double 求面积(double 边长) { return 边长 * 边长; }
int 求面积(int 宽, int 高) { return 宽 * 高; }

// ── 模板成员函数的隐式实例化 ──
template <typename 元素>
元素 容器<元素>::取() const { return 数据; }

// 显式特化的成员定义
string 容器<string>::取() const { return 数据 + "（特化）"; }

// ── 继承 + 虚函数 ──
图形::~图形() {}
double 图形::面积() const { return 0.0; }
const char* 图形::名称() const { return "图形"; }

圆::圆(double 半径值) : 半径(半径值) {}
圆::~圆() {}
double 圆::面积() const { return 3.14159265358979 * 半径 * 半径; }
const char* 圆::名称() const { return "圆"; }

矩形::矩形(double 宽值, double 高值) : 宽(宽值), 高(高值) {}
double 矩形::面积() const { return 宽 * 高; }
const char* 矩形::名称() const { return "矩形"; }

// ── 显式实例化，确保符号进入目标文件 ──
template struct 容器<int>;
template struct 容器<double>;

int 使用模板() {
    容器<int> 甲{42};
    容器<string> 乙{"你好"};
    return 甲.取() + static_cast<int>(乙.取().size());
}

const char* 描述图形(const 图形& 图形对象) {
    return 图形对象.名称();
}

// 多文件工程测试用的公共头文件（英文声明，中文实现）
#pragma once
#include <string>
#include <vector>

// 自由函数重载
int 求面积(int 边长);
double 求面积(double 边长);
int 求面积(int 宽, int 高);

// 类模板 + 显式特化
template <typename 元素>
struct 容器 {
    元素 数据;
    元素 取() const;
};

template <>
struct 容器<std::string> {
    std::string 数据;
    std::string 取() const;          // 注意：特化类里这是普通成员，不是模板成员
};

// 继承 + 虚函数
struct 图形 {
    virtual ~图形();
    virtual double 面积() const;
    virtual const char* 名称() const;
};

struct 圆 : 图形 {
    double 半径;
    explicit 圆(double 半径);
    ~圆() override;
    double 面积() const override;
    const char* 名称() const override;
};

struct 矩形 : 图形 {
    double 宽, 高;
    矩形(double 宽, double 高);
    double 面积() const override;
    const char* 名称() const override;
};

// 变参模板 + 折叠表达式
template <typename... 数>
int 求和(数... 项) { return (int(项) + ... + 0); }

// 供 main 调用，避免模板只在头文件里被内联掉
int 使用模板();
const char* 描述图形(const 图形& 图形对象);

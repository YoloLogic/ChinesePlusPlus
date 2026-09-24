// 模拟 std::vector 的最小形状：英文成员，include guard 用 VEC_H。
// 见同目录 README.md：这组文件是「中文标准库该怎么做」那条设计决定的实测证据。
#ifndef VEC_H
#define VEC_H

namespace my {
template <class T> struct V {
    T *data = nullptr;
    void push_back(T x) { data = new T(x); }
};
}

#endif

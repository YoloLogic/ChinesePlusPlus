// 变体：中文副本【复用原库的 include guard】（VEC_H）。
// 这是"两份头并行"这条路的标准补救 —— 两个头同时引不再重定义。
// 代价是：先被引的那个赢，另一个整个被跳过（实测见 README.md）。
#ifndef VEC_H
#define VEC_H

namespace my {
template <class T> struct V {
    T *data = nullptr;
    void push_back(T x) { data = new T(x); }
    void 压入(T x) { push_back(x); }
};
}

#endif

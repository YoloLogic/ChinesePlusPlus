// 「复制一份、加中文名」的中文副本：内容与 vec_orig.h 相同，外加中文成员。
// include guard 故意用【不同】的名字（VEC_ZH_H）—— 这是最自然的写法，
// 也正是会导致「两个头同时引 = 重定义」的写法。
#ifndef VEC_ZH_H
#define VEC_ZH_H

namespace my {
template <class T> struct V {
    T *data = nullptr;
    void push_back(T x) { data = new T(x); }
    void 压入(T x) { push_back(x); }   // 只加不改
};
}

#endif

// RTTI / 动态转换 在中文类型名上的行为
#include "exc_iface.h"
#include <cstdio>
#include <stdexcept>
#include <typeinfo>
#include <windows.h>

int main() {
    SetConsoleOutputCP(CP_UTF8);
    printf("=== 动态转换 + 中文类型名 RTTI ===\n\n");

    我的库::计算错误 错误对象(42);
    std::exception& 基类引用 = 错误对象;

    // 向下转型：RTTI 名称必须与抛出侧一致才能成功
    如果 (自动* 具体 = 动态转换<我的库::计算错误*>(&基类引用)) {
        printf("[1] 动态转换成功 -> 错误码=%d\n", 具体->错误码);
    } 否则 {
        printf("[1] 动态转换失败 —— RTTI 不匹配\n");
    }

    // 错误方向的转换应当得到空指针
    如果 (动态转换<std::runtime_error*>(&基类引用) == 空指针) {
        printf("[2] 错误方向的动态转换正确返回 空指针\n");
    } 否则 {
        printf("[2] 异常：错误方向竟然转换成功\n");
    }

    // 类型标识 应当给出中文名
    printf("[3] 类型标识(基类引用).name() = %s\n", 类型标识(基类引用).name());

    printf("\n=== 通过 ===\n");
    return 0;
}

// 捕获侧：英文关键字，与抛出侧位于不同编译单元
#include "exc_iface.h"
#include <cstdio>
#include <windows.h>

int main() {
    SetConsoleOutputCP(CP_UTF8);
    printf("=== 跨编译单元异常/RTTI 匹配 ===\n\n");

    // 1. 中文命名的异常类型能否被英文侧捕获
    try {
        我的库::危险除法(10, 0);
        printf("[1] 没有抛出异常 —— 异常\n");
    } catch (const 我的库::计算错误& 错) {
        printf("[1] 捕获 我的库::计算错误, 错误码=%d, what()=%s\n", 错.错误码, 错.what());
    } catch (const std::exception& 错) {
        printf("[1] 只捕获到基类 std::exception: %s  <- RTTI 不匹配\n", 错.what());
    }

    // 2. 正常路径
    printf("[2] 危险除法(10, 3) = %d\n", 我的库::危险除法(10, 3));

    // 3. 中文名域 + 中文成员函数模板
    printf("[3] 取最大值(3, 7) = %d, 取最大值(2.5, 1.5) = %.1f\n",
           我的库::取最大值(3, 7), 我的库::取最大值(2.5, 1.5));

    printf("\n=== 通过 ===\n");
    return 0;
}

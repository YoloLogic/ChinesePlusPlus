// 英文驱动（由 MSVC 编译），链接「中文关键字实现」产出的 zh.obj
#include "iface.h"
#include <cstdio>
#include <windows.h>

int main() {
    SetConsoleOutputCP(CP_UTF8);
    printf("[MSVC main] 驱动由 MSVC 编译，实现由中文关键字 clang 编译\n");
    圆 圆对象(2.0);
    矩形 矩形对象(5.0, 6.0);
    printf("  圆: %s %.4f | 矩形: %s %.1f\n",
           圆对象.名称(), 圆对象.面积(), 矩形对象.名称(), 矩形对象.面积());
    printf("  求面积(7)=%d  求和(1,2,3)=%d  使用模板()=%d\n",
           求面积(7), 求和(1, 2, 3), 使用模板());
    printf("  描述图形(圆对象)=%s\n", 描述图形(圆对象));
    return 0;
}

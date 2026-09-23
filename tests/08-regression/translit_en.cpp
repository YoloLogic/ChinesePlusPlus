// 转译对照（英文版）：与 test_translit_zh.cpp 语义完全等价。
// 用于验证「英文关键字仍然完全可用」——即中英并存没有破坏英文代码。

int 甲 = 1;
int 乙 = 2;

int 相加(int 左, int 右) {
    if (左 > 右) {
        return 左 + 右;
    } else {
        return 左 - 右;
    }
}

int 丙 = 相加(甲, 乙);

// expect: cannot initialize a variable of type
//
// 回退测试：本文件用的诊断【不在】中文表里，必须原样显示英文。
// 脚本对本文件做一条更强的断言：默认编译与加 -fno-chinese-diagnostics
// 编译的日志必须【逐字节相同】—— 这就是「查不到就回退英文」的机器证明。
//
// 注意：这个用例的难点是**一直**挑一个还没进表的诊断。
// 第一批它用的是 err_redefinition，第二批把那条翻掉之后它就失效了
// （脚本立刻报「default: English body present (found=False)」），于是换成这条。
// 教训：每加一批中文，都要回头确认这个文件用的诊断仍然没被翻。
整数 main() { 整数 甲 = "x"; 返回 0; }

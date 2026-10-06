// ============================================================================
//  asan-annotate.cpp -- 顶掉微软的 stl_asan.lib（§18.48 批4）
//
//  WHY
//    MEASURED: `-fsanitize=address` 编 <vector> 时，MSVC 的
//    vendor\msvc-stl\__msvc_sanitizer_annotate_container.hpp 会发一条
//      #pragma comment(lib, "stl_asan")        （即目标文件里的 /DEFAULTLIB:stl_asan）
//    于是链接器按 clang 给的 `-libpath:` 去 **VS 安装目录**里读
//      C:\Program Files\Microsoft Visual Studio\...\VC\Tools\MSVC\<ver>\lib\x64\stl_asan.lib
//    —— 这是**唯一**一处让 bundled（零 VS）地基漏到 VS 目录的链接依赖（实测 /verbose）。
//    该库是 MSVC 工具集的一部分，**不可再发行**，所以不能随包，只能自己顶。
//
//  这个库里到底有什么（实测：`/nodefaultlib:stl_asan` 之后只差一个符号）：
//    只有两个"开关"，头文件里声明为
//      extern "C" extern const bool _Asan_vector_should_annotate;   (容器溢出注解：向量)
//      extern "C" extern const bool _Asan_string_should_annotate;   (容器溢出注解：字符串)
//    以及它们的 `/alternatename` 落点 `..._should_annotate_default`（值 false）。
//    头文件里那两条 `/alternatename:X=X_default` 就是"真符号不在时退回 false"的意思。
//    我们**在 ASan 下就该是 true**（这正是 stl_asan.lib 的取值），所以直接定义 true；
//    非 ASan 的编译根本不会声明/引用这两个符号（实测：普通 C++ 链接读库数不变）。
//
//  真跑验证（不是"编过就算"）：build\_review_own\batch4_judge.ps1 里有一条
//    "容器溢出"用例 —— v.reserve(10); v.push_back(1); v[5]=42;
//    只有注解真的开着，ASan 才会报 container-overflow；关掉就报不出来。
//
//  ASCII only.
// ============================================================================

extern "C" {

//  `extern` 是必需的：C++ 里 namespace 作用域的 `const` 默认是内部链接，
//  没有 extern 就发不出外部符号（这条是实测踩出来的）。
extern const bool _Asan_vector_should_annotate = true;
extern const bool _Asan_string_should_annotate = true;

} // extern "C"

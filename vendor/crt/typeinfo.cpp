// ============================================================================
//  typeinfo.cpp -- 手搓 `??_7type_info@@6B@`（type_info 的 vftable）（§18.48 批4）
//
//  WHY
//    MEASURED: `-fsanitize=address` / `--coverage` 会带进 clang 自带的运行库目标
//    文件（clang_rt.*），它们是开了 RTTI 的 C++ 目标文件，引用
//      `const type_info::`vftable'`  F  `??_7type_info@@6B@`
//    这个符号**只能由 CRT 发**：clang 自己的源码写死了这件事 ——
//      clang/lib/CodeGen/MicrosoftCXXABI.cpp: getTypeInfoVTable()
//        StringRef MangledName("??_7type_info@@6B@");
//        ... ExternalLinkage, /*Initializer=*/nullptr ...
//    也就是说 clang 永远只**引用**它（把它填进每个 RTTI 类型描述符的 VFPtr 字段），
//    从不定义它；微软把它定义在**静态 CRT**（libcmt.lib / vcruntime.lib）里。
//    我们顶掉了 libcmt ⇒ 没人发 ⇒ 链接报
//      lld-link: error: undefined symbol: const type_info::`vftable'
//
//  为什么不能直接用 vendor\compiler-support\vcruntime_typeinfo.h 里的 std::type_info 发
//  （三条都是实测，代价换来的）：
//    ① 那个类在 `namespace std` 里 ⇒ vftable 会叫 `??_7type_info@std@@6B@`，
//       而 clang 要的是**没有 std** 的 `??_7type_info@@6B@`（微软的 ABI 就这样）；
//    ② 光"定义了非内联虚析构"clang **不发** vftable（实测 obj 里只有
//       `??1type_info@@UEAA@XZ`，vftable 一个字节都没有）—— 发多态类的**对象**才行；
//    ③ 单靠 ①② 还不够：本 TU 只要生成任何 RTTI，clang 就会**先**建一个叫
//       `??_7type_info@@6B@` 的**空声明**（它就是类型描述符的 VFPtr），
//       于是真正的 vftable 被改名成 `??_7type_info@@6B@.1`（实测），链接照样差符号。
//
//  HOW
//    本 TU 用 **`-fno-rtti`** 编译（tools\vendor_crt.ps1 里单独加这个开关）：
//      · 没有类型描述符 ⇒ 那个空声明不会出现 ⇒ vftable 拿到**正名**；
//      · vftable 里也不需要 complete object locator（`-GR-` 正常行为）。
//    再配合一个全局名字空间、布局逐字相同的 `type_info` 替身 + 一个它的对象
//    （`zh_type_info_anchor`，"构造多态类对象"才是 clang 发 vftable 的触发条件）。
//    /include:??_7type_info@@6B@（见 tools\make_zhcfg.ps1）负责把它从库成员里拉出来。
//
//  代价：.data 里多 24 字节哑对象（构造/析构平凡，不依赖任何运行时）。换来的是
//    `-fsanitize` / `--coverage` 在 **bundled（零 VS）** 地基下也能链。
//    替身 vftable 的两个槽（scalar/vector deleting destructor）**永远不会被调用**：
//    type_info 对象只由编译器在只读段里生成，从不需要 delete（微软的也一样）。
//
//  `__type_info_root_node`：实测**不是** vcruntime140.dll 的导出（gendef 生成的
//    vcruntime140.lib 里没有它），微软把它定义在静态 CRT 里（type_info 名字链表的表头），
//    我们照做 —— 否则 `type_info::name()` 一被调用就报 undefined。
//
//  ASCII only.
// ============================================================================

#include <vcruntime_typeinfo.h>   // 真正的 std::type_info 长什么样，在这里

extern "C" __type_info_node __type_info_root_node = { nullptr, nullptr };

//  ABI-identical twin, in the GLOBAL namespace on purpose (see WHY ①).
//  Layout must be byte-for-byte the same as std::type_info: the implicit vfptr
//  followed by `__std_type_info_data`. Nothing else is needed -- the compiler only
//  ever reads a type descriptor's `_Data`, never this class's members.
class type_info {
public:
    type_info() noexcept : _Data{} {}
    virtual ~type_info() noexcept;

private:
    mutable __std_type_info_data _Data;
};

type_info::~type_info() noexcept {}

//  The anchor (see HOW ②). Do not remove: without it clang emits no vftable at all.
type_info zh_type_info_anchor;

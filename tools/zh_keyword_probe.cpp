//===--- zh_keyword_probe.cpp - 中文关键字表的编译期自检 ------------------===//
//
// 目的：用真编译器（而不是人眼、也不是脚本）验证 ChineseKeywords.def 是否
//       可以安全地被 clang 的三个使用点展开。
//
// 为什么需要它：
//   这个文件里的检查对应的正是真正构建时会走到、但可能要等很久才走到的
//   三处代码：
//
//     1) clang/lib/Basic/TokenKinds.cpp
//          #define ZH_KEYWORD(NAME, ZH, FLAGS) case kw_ ## NAME: return #ZH;
//        NAME 拼错 → “no enumerator named kw_xxx” → 编译失败。
//
//     2) clang/lib/Basic/IdentifierTable.cpp
//          #define ZH_KEYWORD(NAME, ZH, FLAGS) \
//            AddKeyword(#ZH, tok::kw_ ## NAME, FLAGS, LangOpts, *this);
//        FLAGS 抄错 → 中文关键字在错误的语言模式下被识别（或不被识别）。
//        这类错误【不会】报编译错误，只会静默出错，所以必须显式比对。
//
//     3) clang/lib/Parse/ParseDeclCXX.cpp
//          #define ZH_VIRT_SPECIFIER(NAME, ZH) \
//            Ident_zh_##NAME = &PP.getIdentifierTable().get(#ZH);
//
//   第 3 处曾经写成 get(ZH)（漏了 #），2026-09-22 的构建就是这样失败的：
//       ChineseKeywords.def(207,1): error C2065: “重写”: 未声明的标识符
//   当时的探针把 ZH_VIRT_SPECIFIER 定义成空宏，所以完全没看见。
//   教训：【只验 .def 表本身是不够的，宏体必须一起镜像】——见本文件第二部分的
//   Replicate_* ，它们逐字照抄上述三处的宏体，只把 clang 内部对象换成假对象。
//
// 注意：kw_* 的合法名字并不只来自 TokenKinds.def，还来自它 include 的
//       Traits.inc（TableGen 由 Traits.td 生成，sizeof/alignof 在里面）、
//       OpenCLImageTypes.def、RegularKeywordAttrInfo.inc。所以本文件不自己
//       推演宏规则，而是直接 include 真正的 clang 头文件，让预处理器和
//       编译器给出权威答案。
//
// 用法（几秒，只做语法/语义检查，不生成任何目标文件）：
//
//   clang++ -fsyntax-only -std=c++17 -Wno-unused \
//     -I E:/Chinese++/LLVM-main/clang/include \
//     -I E:/Chinese++/LLVM-main/llvm/include \
//     -I E:/Chinese++/build/tools/clang/include \
//     -I E:/Chinese++/build/include \
//     E:/Chinese++/tools/zh_keyword_probe.cpp
//===----------------------------------------------------------------------===//

#include "clang/Basic/TokenKinds.h"
#include "llvm/ADT/StringRef.h"

// clang 源码的惯例：tok::kw_* 与 KEYALL 等标志都在 namespace clang 里。
using namespace clang;

//===========================================================================
// 第一部分：.def 表本身
//===========================================================================

//---------------------------------------------------------------------------
// 权威值：英文原定义给出的 flags。
//
// TokenKinds.def 里的 CXX11_KEYWORD / TYPE_TRAIT_1 / UNARY_EXPR_OR_TYPE_TRAIT
// 等家族，最终都会展开成 KEYWORD(名字, 标志或)，所以这里只接管 KEYWORD 一个
// 宏，就能拿到每一个 kw_* 的权威 flags。其余家族用 TokenKinds.def 自带的
// #ifndef 空宏兜底即可。
//---------------------------------------------------------------------------
static constexpr unsigned EnglishFlags(tok::TokenKind Kind) {
  switch (Kind) {
#define KEYWORD(X, Y) case tok::kw_##X: return Y;
#include "clang/Basic/TokenKinds.def"
  default:
    break;
  }
  return 0;
}

//---------------------------------------------------------------------------
// 中文表声明的 flags。
//
// 同时，重复的 NAME 会在这里变成重复的 case 标签，编译器直接报错。
//---------------------------------------------------------------------------
static constexpr unsigned ChineseFlags(tok::TokenKind Kind) {
  switch (Kind) {
#define ZH_KEYWORD(NAME, ZH, FLAGS) case tok::kw_##NAME: return FLAGS;
#define ZH_VIRT_SPECIFIER(NAME, ZH)
#define ZH_OPERATOR_KEYWORD(ZH, ALIAS)
#include "clang/Basic/ChineseKeywords.def"
  default:
    break;
  }
  return 0;
}

//---------------------------------------------------------------------------
// 检查一 + 检查二：每个中文关键字必须对应真实存在的 tok::kw_*，
//                且不能有重复 NAME（重复 → 重复 case → 编译错误）。
//
// 这个 switch 与 clang/lib/Basic/TokenKinds.cpp 的写法逐字一致（含 #ZH），
// 所以它既能验 token 是否存在，也能验 #ZH 字符串化是否正确。
//---------------------------------------------------------------------------
static const char *KeywordSpelling(tok::TokenKind Kind) {
  switch (Kind) {
#define ZH_KEYWORD(NAME, ZH, FLAGS) case tok::kw_##NAME: return #ZH;
#define ZH_VIRT_SPECIFIER(NAME, ZH)
#define ZH_OPERATOR_KEYWORD(ZH, ALIAS)
#include "clang/Basic/ChineseKeywords.def"
  default:
    return nullptr;
  }
}

//---------------------------------------------------------------------------
// 检查三：运算符替代拼写（第七节）必须对应真实存在的 tok:: 值。
//
// 它们不是关键字 token，走的是 AddCXXOperatorKeyword()，映射到 tok::ampamp
// 这类“标点 token”，所以名字必须和 TokenKinds.def 里的
// CXX_KEYWORD_OPERATOR(and, ampamp) 第二列一致。
//---------------------------------------------------------------------------
static const tok::TokenKind OperatorAliases[] = {
#define ZH_KEYWORD(NAME, ZH, FLAGS)
#define ZH_VIRT_SPECIFIER(NAME, ZH)
#define ZH_OPERATOR_KEYWORD(ZH, ALIAS) tok::ALIAS,
#include "clang/Basic/ChineseKeywords.def"
};

//---------------------------------------------------------------------------
// 检查四（最重要）：中文表里每一行的 FLAGS 必须与英文原定义逐位相同。
//
// 抄错 FLAGS 不会报编译错误，只会让中文关键字在错误的语言模式里生效，
// 所以这一条只能靠显式比对。
//---------------------------------------------------------------------------
#define ZH_KEYWORD(NAME, ZH, FLAGS)                                            \
  static_assert(ChineseFlags(tok::kw_##NAME) == EnglishFlags(tok::kw_##NAME),  \
                "flags 与英文原定义不一致: " #NAME);
#define ZH_VIRT_SPECIFIER(NAME, ZH)
#define ZH_OPERATOR_KEYWORD(ZH, ALIAS)
#include "clang/Basic/ChineseKeywords.def"

//---------------------------------------------------------------------------
// 第八节（上下文关键字 module / import）在本文件里【故意不接管】，上面每一处
// include 都让它走 .def 自带的 #ifndef 空宏。
//
// 原因：它的注册点是对【真】IdentifierInfo 的调用
//     get("模块").setModuleKeyword(true);
// 用假对象镜像只能验证「我自己的镜像」，价值为零（这正是 ParseDeclCXX 那次
// 漏 # 没被本探针发现的同一个坑）。
//
// 所以它的真实验证由「对 IdentifierTable.cpp 本身跑 -fsyntax-only」承担：
// setter 名字写错会在那里第一时间报错。
//---------------------------------------------------------------------------

//===========================================================================
// 第二部分：镜像三个真实使用点的【宏体】
//
// 上面只验了表；真正出过错的是宏体。这里用最小假对象复现三处的宏体写法，
// 任何“宏体写错”都会在编译期暴露。
//===========================================================================

namespace replica {

struct IdentifierInfo {};

// 真实代码里 get() 返回 IdentifierInfo&，外面取地址得到 IdentifierInfo*。
struct IdentifierTable {
  IdentifierInfo &get(llvm::StringRef Name);
};

struct Preprocessor {
  IdentifierTable Table;
  IdentifierTable &getIdentifierTable() { return Table; }
};

struct LangOptions {
  bool CXXOperatorNames = true;
};

} // namespace replica

using replica::IdentifierInfo;
using replica::IdentifierTable;
using replica::LangOptions;
using replica::Preprocessor;

static Preprocessor PP;
static IdentifierInfo *Ident_zh_override = nullptr;
static IdentifierInfo *Ident_zh_final = nullptr;

//---------------------------------------------------------------------------
// 镜像 3：clang/lib/Parse/ParseDeclCXX.cpp
//
//   这里就是要守住 get(#ZH) 的那个 #。
//   写成 get(ZH) → “重写”: 未声明的标识符 → 编译失败（正是曾发生的事故）。
//---------------------------------------------------------------------------
static void Replicate_ParseDeclCXX() {
#define ZH_VIRT_SPECIFIER(NAME, ZH) \
    Ident_zh_##NAME = &PP.getIdentifierTable().get(#ZH);
#define ZH_KEYWORD(NAME, ZH, FLAGS)
#define ZH_OPERATOR_KEYWORD(ZH, ALIAS)
#include "clang/Basic/ChineseKeywords.def"
}

//---------------------------------------------------------------------------
// 镜像 2：clang/lib/Basic/IdentifierTable.cpp 的 AddKeywords()
//
//   两处 StringRef(#ZH) 与一处 AddKeyword(#ZH, …) 都必须字符串化。
//   参数名故意也叫 LangOpts，与真实代码一致。
//---------------------------------------------------------------------------
struct FakeKeywordTable;

static void AddKeyword(llvm::StringRef Keyword, tok::TokenKind Code, unsigned Flags,
                       const LangOptions &LangOpts, FakeKeywordTable &Table);
static void AddCXXOperatorKeyword(llvm::StringRef Name, tok::TokenKind K,
                                  FakeKeywordTable &Table);
static void MarkIdentifierAsKeywordInCpp(FakeKeywordTable &Table,
                                         llvm::StringRef Name);

struct FakeKeywordTable {
  void AddKeywords(const LangOptions &LangOpts) {
#define ZH_KEYWORD(NAME, ZH, FLAGS) \
    AddKeyword(#ZH, tok::kw_##NAME, FLAGS, LangOpts, *this);
#define ZH_OPERATOR_KEYWORD(ZH, ALIAS)                                        \
    if (LangOpts.CXXOperatorNames)                                            \
      AddCXXOperatorKeyword(llvm::StringRef(#ZH), tok::ALIAS, *this);          \
    else                                                                      \
      MarkIdentifierAsKeywordInCpp(*this, llvm::StringRef(#ZH));
#define ZH_VIRT_SPECIFIER(NAME, ZH)
#include "clang/Basic/ChineseKeywords.def"
  }
};

static void AddKeyword(llvm::StringRef Keyword, tok::TokenKind Code, unsigned Flags,
                       const LangOptions &LangOpts, FakeKeywordTable &Table) {}
static void AddCXXOperatorKeyword(llvm::StringRef Name, tok::TokenKind K,
                                  FakeKeywordTable &Table) {}
static void MarkIdentifierAsKeywordInCpp(FakeKeywordTable &Table,
                                         llvm::StringRef Name) {}

//===========================================================================
// 让上面这些函数与数组“被使用”，避免 -Wunused 噪音（不影响任何检查）。
//===========================================================================
void zh_keyword_probe_anchor(void);
void zh_keyword_probe_anchor(void) {
  (void)KeywordSpelling(tok::kw_int);
  (void)OperatorAliases;
  (void)ChineseFlags(tok::kw_int);
  (void)EnglishFlags(tok::kw_int);
  Replicate_ParseDeclCXX();
  FakeKeywordTable Table;
  LangOptions LO;
  Table.AddKeywords(LO);
}

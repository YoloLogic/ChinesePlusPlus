# ChineseTypeScript —— 第四条产品线（网页那一角）

> 名称一律写 **ChineseTypeScript**（不是 "ChineseScript"）。
> 文件扩展名 **`.chts`**。
>
> 本文是这条产品线在 Chinese++ 仓库里的**登记与证据**。工作副本在
> `E:\ChineseTypeScript`（独立 git 仓，底本为上游镜像，**不是**本仓库的子目录）。

## 一、这是什么

Chinese++ 的三角定位是「最快的（C++）/ 最全面的（Python）/
最适合浏览器页面的（JS 或 TS 魔改）」。ChineseTypeScript 就是**网页那一角**：

把 Go 版的 TypeScript（也就是今天 `tsc` 的本体，`microsoft/typescript-go`）汉化，
让**汉语关键字与英文落成同一个 token**：

```
汉语 `如果`  ─┐
              ├─→  ast.KindIfKeyword
英文 `if`    ─┘
```

于是词法分析之后的一切（parser / binder / checker / printer / 语言服务）
**一行都不用改** —— 与本项目改 clang 的手法完全同构（`ChineseKeywords.def` 那套）。

三条硬要求（都已被机器判定）：

1. **英文永不删除**：英文 `.ts` 的产物与上游基线**逐字节一致**；
2. **产出的仍是标准 JS**：`.chts` 编译出的 js 用**英文关键字**，能被 node 直接运行；
3. **随便拿一个开源 TypeScript 项目照样编得过**。

## 二、底本与许可

| 项 | 值 |
|---|---|
| 上游 | `microsoft/typescript-go`（Go 语言的原生 tsc） |
| 取得 | gitee 镜像克隆（GitHub 直连太慢，实测 curl 28） |
| 基线 commit | `e26b8d24bee09bf66d59941912166c5aa7975d20` |
| 许可 | **Apache-2.0**（可修改、可再发行；需保留声明） |
| 上游原样副本 | `E:\TypeScript源代码`（**不要改**，是比对基准） |
| 本地提交 | `c2589b3d`、`d4b9c841`、`60b94c0d`、`51e5f5d8`、`9ef62083`（五个提交，均未 push） |

选 TS 7（Go 版）而不是经典 TS 5.x/6.x 的理由：**它就是今天 `tsc` 的本体**
（npm `typescript@7.x` 只是个去找原生二进制的薄壳），且**关键字表就在一处**。

## 三、扩展名为什么是 `.chts`

用户裁定：「文件格式我建议 cts，cts 被占用了就用 chts」。
**`.cts` 确凿被上游占用，且是语义性占用、不可挪用**，证据：

| 证据 | 位置 |
|---|---|
| 注释「Check if the file is .cts or .cjs (CommonJS-specific extensions)」 | `checker/checker.go:5777` |
| `ext = core.IfElse(preferTs, ".cts", ".cjs")` | `checker/checker.go:15547` |
| `.cts` 列在 `ExtensionsNotSupportingExtensionlessResolution` 里 | `tspath/extension.go` |

故取 **`.chts`**。所有扩展名表里**一律追加在末尾**，使 `.ts/.tsx/.d.ts`
的既有优先级与解析顺序一个字节都不变。

## 四、改动清单：上游源码只动了 5 个文件

| # | 文件 | 改动 |
|---|---|---|
| 1 | `scanner/scanner.go` | `GetIdentifierToken` 放开 ASCII 闸：非 ASCII 标识符查独立表 `zhTextToKeyword` |
| 2 | `tspath/extension.go` | 新增 `ExtensionChts`；并入 `extensionsToRemove`（**决定输出名**）、`ExtensionIsTs`、各受支持扩展名表、声明文件扩展名 |
| 3 | `core/core.go` | `.chts` → `ScriptKindTS` |
| 4 | `module/resolver.go` | `extensionIsOk` 白名单加 `.chts`；`tryAddingExtensions` 加无扩展名分支 + 新增 `case ExtensionChts` |
| 5 | `module/util.go` | `GetResolutionDiagnostic` 的「永远允许」白名单加 `.chts`（否则报 TS6263 说它是"任意扩展名"） |

**parser / binder / checker / printer / 语言服务零改动。**

### 关键设计：汉语别名为什么必须【独立成表】

`scanner.go` 的 `tokenToText` 是**由 `textToToken` 倒排**得到的：

```go
for text, kind := range textToToken { result[kind] = text }   // ← Go map 顺序随机
```

而 `printer.go` 的 `writeTokenText` 直接用它落盘。**Go 的 map 遍历顺序是随机的**，
所以中文键一旦混入 `textToKeyword`／`textToToken`，`tokenToText[KindIfKeyword]`
就会在 `"if"` 与 `"如果"` 之间**随机**取值 —— 生成的 js 会**不确定地**含中文关键字，
那是**非法 JS**。

⇒ 这就是「独立成表」这条设计约束的来源（**有据，非推测**），
并由 `zh_keywords_test.go` 的 `TestTokenToTextHasNoChinese` 机器校核。

### 教训：改「横切」属性要用同级扩展名反查全仓

第 4、5 处是**一开始漏掉的**。第一版只改了扩展名表，结果
`导入 { x } 来自 "./数学"` 报 TS2307 找不到模块 —— `--traceResolution` 显示
候选只试 `.ts .tsx .d.ts .js .jsx`。根因是解析器里另有一张**手写白名单**
`extensionIsOk`，逐扩展名列举，`.chts` 不在其中，候选被直接过滤掉。

**做法**：用 `ExtensionCts` 反查全仓所有出现点，再逐处判断「该不该带上 `.chts`」，
同时分清哪些是 **CJS 语义**（`.cts`、`.cjs` 那一类，`.chts` **不该**跟着进）。

## 五、词表与工具链（绝不靠人记得）

| 角色 | 文件（都在 `E:\ChineseTypeScript`） |
|---|---|
| 译名**单一真源** | `tsc/internal/scanner/zh_keywords.txt`（85 行 `<英文关键字> <中文译名>`） |
| 生成器 | `tsc/cmd/genzhkeywords`（`go run ./cmd/genzhkeywords`，`-check` 供校核） |
| 关键字机器守卫 | `tsc/internal/scanner/zh_keywords_test.go`（9 条） |
| 扩展名机器守卫 | `tsc/internal/tspath/chts_extension_test.go`、`tsc/internal/core/chts_scriptkind_test.go` |
| 共享检查器 | `tests-chts/zhcheck.ps1` |
| 四套判定 | `tests-chts/judge_chts.ps1` / `judge_proj.ps1` / `judge_oss.ps1` / `judge_gotest.ps1` |
| 一条命令全跑 | `tests-chts/run_all.ps1` |

生成器**不信任任何手写清单**：它自己解析 `scanner.go` 的 `textToKeyword`
得到「英文关键字 → `ast.Kind`」，再与词表比对。因此**漏译、多译、译名重复、
汉字数不在 2–6** —— 一律报错退出，不静默。

### 与 Chinese++ 关键字的关系

**同词同义**。英文词相同者复用 Chinese++ 的既定译名
（`if`→如果、`else`→否则、`class`→类型、`break`→跳出、`namespace`→名域 …），
并遵守同一条**定则**：**译名 2–6 个汉字、唯一、不含 ASCII**。

TypeScript 里 `class` 与 `type` 并存，故 `class`→`类型`（沿用 Chinese++ 定例）、
`type`→`类型别名`。

### 词表实测

* 条数 **85**（与 `scanner.go` 的 `textToKeyword` 精确 1:1，无缺无多）
* 译名唯一性：**全部唯一**；一词一译
* 2–6 汉字定则：**全部合规**（2 字 71 条、3 字 12 条、4 字 2 条）
* 最长译名：`局部变量`(let)、`类型别名`(type)，4 汉字 / 12 字节

## 六、判定证据（四套，全绿；每套都能被任何人重跑）

```
judge_chts.ps1   11/11（第 8 节单独钉 `--strict`：同样编译通过、产物 node 真跑通过）
judge_proj.ps1   15/15
judge_oss.ps1    语料 = 上游官方 conformance 目录里【全部】5894 个 .ts/.tsx（排除 .d.ts）
                 全量跑：【诊断输出 + 退出码】5894/5894 逐字节相同（一个不落）
                 另抽 300 个：产物【逐字节】300/300 相同
                 （-Sample N 抽样、-Sample 0 全量；抽样 600 时同样是 600/600 与 60/60）
judge_gotest.ps1  4/4（上游自带 Go 测试全集，跑两遍：基线 vs 工作副本）
                 基线失败包 = astnav（缺 node_modules/typescript）、
                              fswatch（非管理员无建符号链接特权）—— 环境问题
                 工作副本多出的失败包 = tsctests、testrunner —— 全是 baseline 文本差异
                 逐行核对：111 个 baseline 文件 111/111 合规，
                           431 条新增行 + 20 条被改行，全部可用「插入 .chts」解释
```

最关键的两条：

* **英文路径逐字节不变**：同一个 `demo_en.ts`，用上游基线 tsc 与本编译器分别编译，
  产物 SHA256 都是 `BD88EB8023D5F40E…`。
* **汉语源真跑**：`.chts` → `.js`（不是 `.chts.js`）→ node 真跑，
  stdout 与英文对照**完全一致**；产物里 85 个译名**一个都没作为关键字出现**。

### 全集判定为什么必须「逐行可解释」

加新扩展名会**自然地**改变两处文本：`--traceResolution` 的候选列、
诊断消息里「受支持扩展名」那一行。这类差异是**正确且预期**的，
但若不逐行核对，就无法把「预期的差异」与「真把 `.ts` 顺序弄乱了」区分开。
故判据为：**允许差异存在，但每一行都必须能用「插入 `.chts`」解释**
（把新增行里的 `'.chts', ` 去掉后，必须与某条旧行逐字相同）。

## 七、判据自己也会错（本轮踩了五次，全部记账）

1. **子串匹配**：字符串 `"异常已捕获"` 含子串「捕获」、合法标识符 `变量名` 含「变量」
   → 改为「剥掉注释与字符串后，按**汉字连续段整段**比对」。
2. **注释未剥离**：源注释里写了「导入 … 来自」，被 tsc 原样保留进产物。
3. **字面写错**：只导入不导出的产物里只有 `exports, "__esModule"`，没有 `exports.`。
4. **判据过严**：写「不许有被改行」，而诊断消息里列举扩展名的那行**本来就该**多个 `.chts`。
5. **自写单测断言错**：断言「每组首位都是 `.ts`」，而扩展名组是**按模块种类分**的
   （只有标准组首位是 `.ts`）。

> **纪律：凡判据报错，先自证判据，再怀疑被测物。**

## 八、已知局限（诚实登记，别当成已完成）

1. **汉语关键字在所有文件里都生效**，不限于 `.chts`。这是为「改一处覆盖整条链」
   而选的全局方案；实测真实 TS 语料**零回归**，但它确实意味着用户把
   `对象`/`变量`/`函数` 这类词当**标识符**用会撞。英文关键字永远可写，是逃生通道。
   （改成「仅 `.chts` 生效」需把 `GetIdentifierToken` 从包级函数改为扫描器方法
   并逐处传标志，属未做项。）
2. **`.d.chts` 声明文件不支持**。
3. **语言服务尚未把汉语关键字加入补全建议**（`GetViableKeywordSuggestions` 仍只给英文）。
4. **诊断信息未汉化**（Chinese++ 侧已汉化 7344 条；ChineseTypeScript 侧未做）。
5. **未打包、未发布**：没有面向用户的发行包，也没有 `chtsc` 之类的独立命令名。

上面每一条的「怎么接着做」（落点文件、注意事项、会踩什么坑）都写在
工作副本的 `E:\ChineseTypeScript\下一步.md` 里，连同「已经踩过、别再踩的坑」一张表。

## 九、环境（供复核者）

* **Go 1.27.1** 装在 `E:\Go`（C 盘紧张，一切安装放 E 盘）；
  模块缓存 `E:\gopath\pkg\mod`，构建缓存 `E:\gopath\build-cache`；
  `GOPROXY=https://goproxy.cn,direct`。
* **下载教训**：国内镜像实测仅 ~98 KB/s，且 `Invoke-WebRequest` **攒内存不落盘**
  （会出现「下了几分钟仍 0 MB」的假象）；一律用 `curl -C -` 断点续传 + SHA256 校验。
* node v24.15（跑产物用）；基线工作树在 `E:\cts-base`（`git worktree`，
  由判定脚本自动建立）。

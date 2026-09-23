// expect: 未知的类型名（类型名） 'vecotr'；你是不是想写（类型名） 'vector'？
// expect: （名字） 'vector' 在此声明
// forbid: did you mean
// forbid: declared here
//
// "did you mean" 变体：err_unknown_typename 早就翻了，但 clang 只要能给出建议
// 就走 suggest 变体 —— 翻了主句等于把初学者最需要的那半句留成英文。
// 本用例顺带覆盖 note_previous_decl / note_entity_declared_at / note_callee_decl
// （三个 ID 英文都是 "%0 declared here"，中文也必须一样）。
// 对应诊断：err_unknown_typename_suggest
结构 vector { };
vecotr 甲;

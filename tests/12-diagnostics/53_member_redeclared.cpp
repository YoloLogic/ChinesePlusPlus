// expect: 类成员不能被重新声明
// forbid: cannot be redeclared
//
// 类成员被重复声明。err_member_redeclared 与 ext_member_redeclared 英文逐字相同，
// 两个一起翻（只翻一个就会中英并排）。实测只触发到 err_member_redeclared；
// ext_member_redeclared 没找到触发方式 —— 这一点如实写在 .def 的注释里。
// 对应诊断：err_member_redeclared（ext_member_redeclared 同文，无独立用例）
结构 S { void f(); void f(); };

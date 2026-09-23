// expect: 缺少（种类） 非限定标识符
// forbid: expected unqualified-id
//
// 拿关键字当变量名。中文表里这条是 %select{标识符|非限定标识符}0，
// 所以本文件同时验证「%select 的分支被完整保留」。
// 注意「缺少」与后面的词之间**保留一个空格**：汉字连成一长串不利阅读。
// 对应诊断：err_expected_unqualified_id
整数 main() { 整数 如果 = 1; 返回 0; }

// Negative: a spelling that is NOT in ChineseDirectives.def must still be
// rejected. Without this, a checker could not tell "all 22 spellings work" from
// "anything after # is accepted".
//
// `#否则若定义` is deliberately one character away from `#否则若已定义`.
// `#elsedef` is the English equivalent typo (there is no such directive).
#否则若定义 1
#elsedef 1
int x;

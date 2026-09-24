// `-E` must echo the directive with the spelling the user WROTE, not normalise
// it to English. Two reasons:
//   1) a preprocessed file has to be feedable back to the compiler unchanged,
//      and the user's own spelling is the least surprising round-trip
//   2) normalising would make the Chinese spelling a second-class citizen in
//      every tool that reads `-E` output (only our compiler accepts it)
// check.ps1 asserts the byte sequence U+0023 U+5305 U+542B appears in the
// `-E -dI` output.
#包含 "inc_a.h"

int x = FROM_HEADER;

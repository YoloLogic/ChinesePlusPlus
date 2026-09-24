// expect: blocks 支持已禁用：请用 -fblocks 编译，或者改用 OpenCL C 2.0，或带 __opencl_c_device_enqueue 特性的 OpenCL C 3.0
// forbid: blocks support disabled
//
// OpenCL 模式下用了 block 字面量。本文件加 -x cl -cl-std=CL1.2。
// 对应诊断：err_blocks_disable
void f(){ ^{} ; }

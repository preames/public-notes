; NOTE: Assertions have been autogenerated by utils/update_llc_test_checks.py UTC_ARGS: --version 2
; RUN: llc -mtriple=riscv64 -mattr=+v,+unaligned-scalar-mem < %s | FileCheck %s

target datalayout = "e-m:e-p:64:64-i64:64-i128:128-n32:64-S128"
target triple = "riscv64-unknown-linux-gnu"

; TODO: Reverse order of stores to assit prefetcher - this case doesn't matter
; but imagine a loop zeroing 15 byte structures in an array (with something to
; prevent compiler merging it into one memset)
define void @memset_15(ptr %p) {
; CHECK-LABEL: memset_15:
; CHECK:       # %bb.0: # %entry
; CHECK-NEXT:    sd zero, 7(a0)
; CHECK-NEXT:    sd zero, 0(a0)
; CHECK-NEXT:    ret
entry:
  tail call void @llvm.memset.p0.i64(ptr align 8 %p, i8 0, i64 15, i1 false)
  ret void
}

declare void @llvm.memset.p0.i64(ptr nocapture writeonly, i8, i64, i1 immarg)
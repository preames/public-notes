-------------------------------------------------
Overall status of RISCV in LLVM
-------------------------------------------------

This document contains an initial survey of gaps in the RISCV LLVM toolchain ecosystem.  It is being written in May 2022 as I come up to speed on RISCV, and start to wrap my head around the shape of things in general.  It may or may not stay current, so if you're reading this long after the date it was written, keep in mind it may be out of date.  All of the analogous docs I could find online certaintly were!

.. contents::

Functional
----------

LLD doesn’t handle R_RISCV_ALIGN
================================

The align directive requires linker relaxation to be functionally correct.  Currently, unless -mrelax is specified explicitly LLVM's assembler does not emit these relocations.  GCC does, and as a result, object files compiled by GCC can not be linked by LLD.

`maskray has a writeup <http://maskray.me/blog/2021-03-14-the-dark-side-of-riscv-linker-relaxation>_1 on the topic.

gkm has a patch up `<https://reviews.llvm.org/D125036>_`.  This was split off an earlier patch which included both support for the functional fix and the broader topic of linker optimization and relaxation.  

llvm-objdump reports zero size for gcc generated binaries
=========================================================

I have been told that llvm-objdump is reporting zero sizes and failing to disassemble certain gcc compiled object files.  No details available at this time, and issue has not been confirmed with a test case.

Testing Infrastructure
----------------------

No public RISCV llvm build bot
==============================

The RISCV target is built by default, and thus LIT tests do run widely.  The part that’s missing is the execution testing on an actual RISCV environment.  This gap means we’re more likely to miss linkage and dynamic loading issues, or generally any issues which requires interaction between multiple components of the toolchain.

ISEL Fuzzing Disabled
=====================

OSS Fuzz used to do fuzzing of various LLVM backends.  This helps to find recent regressions by finding examples which trigger crashes and assertion failures in newly introduced code.  However, due to a build configuration problem, this was recently disabled.  We need to renable this in general, but also add RISCV to the list of fuzzed targets.  

See `discussion here <https://github.com/google/oss-fuzz/pull/7179#issuecomment-1092802635>_` and linked pull requests on the OSS Fuzz repo.

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

`maskray has a writeup <http://maskray.me/blog/2021-03-14-the-dark-side-of-riscv-linker-relaxation>`_ on the topic.  See also `this llvm bug <https://github.com/llvm/llvm-project/issues/44181>`_.

gkm has a patch up `<https://reviews.llvm.org/D125036>`_.  This was split off an earlier patch which included both support for the functional fix and the broader topic of linker optimization and relaxation.  

llvm-objdump reports zero size for gcc generated binaries
=========================================================

I have been told that llvm-objdump is reporting zero sizes and failing to disassemble certain gcc compiled object files.  No details available at this time, and issue has not been confirmed with a test case.

Concerning items in LLVM issue tracker
======================================

Skiming through the issue tracker for "riscv", I see a couple of concerning looking items.

*  [SelectionDAGISel] Mysteriously dropped chain on strict FP node. `#54617 <https://github.com/llvm/llvm-project/issues/54617>`_.  This appears to be a wrong code bug for strictfp which affects RISCV.
*  [RISCV] Crash in -loop-vectorize pass (BasicTTIImplBase<llvm::RISCVTTIImpl>::getCommonMaskedMemoryOpCost) `#53599 <https://github.com/llvm/llvm-project/issues/53599>`_
*  [RISCV] wrong vector register alloc in vector instruction `#50157 <https://github.com/llvm/llvm-project/issues/50157>`_.  Appears to be a miscompile of vgather intrinsic, and may hint at a larger lurking issue.


Testing Infrastructure
----------------------

No public RISCV llvm build bot
==============================

The RISCV target is built by default, and thus LIT tests do run widely.  The part that’s missing is the execution testing on an actual RISCV environment.  This gap means we’re more likely to miss linkage and dynamic loading issues, or generally any issues which requires interaction between multiple components of the toolchain.

ISEL Fuzzing Disabled
=====================

OSS Fuzz used to do fuzzing of various LLVM backends.  This helps to find recent regressions by finding examples which trigger crashes and assertion failures in newly introduced code.  However, due to a build configuration problem, this was recently disabled.  We need to renable this in general, but also add RISCV to the list of fuzzed targets.  

See `discussion here <https://github.com/google/oss-fuzz/pull/7179#issuecomment-1092802635>`_ and linked pull requests on the OSS Fuzz repo.


Performance
-----------

LLD - Linker Optimization and Relaxation
========================================

LLD does not currently implement either linker optimization (substituting one code sequence for a smaller/faster one when resolving relocations) or relaxation (shrinking code size exploiting smaller sequences found via optimization.)  Note that this is different from the functional issue described above, though the infrastructure to fix may end up being the same.

Fixed Length Loop Vectorization
===============================

Fixed length vectorization is currently disabled by default, but can be enabled by explicitly configuring the min vector length at the command line.  Alternatively, you can now specifify the special value -1 to mean "do what the target cpu and extensions say" (e.g. take vector length from Zl128).  

I have not yet heard of any functional issues here, but some may exist.  Given this is a fairly well exercised code path in the vectorizer, likely issues will be in codegen and the backend.

From a performance standpoint, the status is unclear.  I've been told we need to improve the cost model, but don't currently have a set of reproducers to demonstrate where our cost model needs improvement.

One particular point worth noting is that vectorizing long hot loops (with a classic vector loop + scalar epilogue) and vectorizing short loops (with vector epilogue or tail folding) will involve slightly different work and may be enabled at different times.

For epilogue handling, there's an open question as to whether mask predication will be performant enough or whether we will need explicit vector length predication.  The later involves the VP intrinsics discussed later.

Note that fixed length vectorization is likely to remain the default for -mtune configurations even once we have support for scalable.  Or at least, the decision to turn it off is a separate one from having support for scalable vectorization.

Scalable Loop Vectorization
===========================

Scalable vectorization is mostly relevant for code which is compiled against a generic RISCV target.  Such code will be important, but is likely to be biased away from the hotest of vector kernels.  Given that, producing good quality code at minimal code size is likely to be relatively more important.

Hot Loops
+++++++++

ARM SVE has pioneered support in the loop vectorizer for runtime vector lengths in the main loop.  Starting with a vector body + scalar epilogue lowering may be a reasonable intermediate for scalable compilation.

Short Loops
+++++++++++

The goal here is to generate a single vector loop which uses either masking or vector lengths to handle the epilogue iterations.  This is a much longer term project.

For explicit masking, we may be able to reuse existing infrastructure in the vectorizer.  The key question - which I don't think anyone actually knows yet - is whether the resulting code can be made sufficiently performant.  Of particular uncertainty is the importance (for hardware performance) of using vector length vs predication, and if vector length is strongly preferred whether vector length changes can be reliably pattern matched from mask predicated IR.

For IR level vector lengths, the consensus approach appears to be to use the VP intrinsic infrastructure and there is a public repo which has some degree of prototyping.  I have not evaluated it in depth.

At a minimum, here are the major tasks involved:
* Teach the optimizer about basic properties of VP intrinsics (e.g. constant folding, known bits, instcombine, etc..)
* Audit optimizer bailouts on scalable vectors and handle as uniformly as possible.  
* Teach the cost models about VP intrinsics
* Teach the vectorizer how to generate scalable vectorized loops (POC patches on phabricator, but very stale)

SLP Vectorization
=================

Listing separately to make clear this is not the same work as loop vectorization.  I don't currently see a way to do variable length SLP vectorization, so this is likely to overlap with the fixed length loop vectorization to some degree.


Performance (Minor)
-------------------

Maybe interesting cases from the LLVM issue tracker:
*  Unaligned read followed by bswap generates suboptimal code #48314

   

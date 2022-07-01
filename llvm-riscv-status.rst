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

This may be related to the suspected ELF interpretation differences below.

Frame setup problems
====================

I've been told from a couple sources that frame setup is not correct.  We know have at least two confirmed issues, but where there are two, there are probably more.  Known issues:

* Its been mentioned to me that scalable allocas may not be lowered correctly.  Possibly in combination with frame alignment interactions.
* Fraser fixed a couple of misaligned RVV stack problems recently. 
* Kito has a separate issue around exception handling.  `Tracked in 55442 <https://github.com/llvm/llvm-project/issues/55442>`_ 

LLD vs LD differences in ELF interpretation
===========================================

At a recent LLVM RISC-V sync-up, it was mentioned that LLD and LD disagree on interpretation of certain ELF fields.  As a result, using LLD to link gnu generated object files and LD to link LLVM generated ones was thought to be unreliable.

No specifics currently known, so first step here is to find differences if any.  Adopting something similiar to the MSVC differential abi fuzzing that was done a few years back might be very worthwhile.

LLDB Support
============

In tree, LLDB apparently does not fully work on RISCV.  Exact status unclear.  I've heard reports that with out of tree changes, using it for remote debugging does work, but I don't know where these changes are or progress on getting them upstream.

Workaround: GDB appears to work well with LLVM generated code, and is widely used for this purpose.

Debug info quality in the backend is unclear.  Would be good to do a systematic search for issues ala the Sony efforts from a few years ago.

Concerning items in LLVM issue tracker
======================================

Skiming through the issue tracker for "riscv", I see a couple of concerning looking items.

*  [SelectionDAGISel] Mysteriously dropped chain on strict FP node. `#54617 <https://github.com/llvm/llvm-project/issues/54617>`_.  This appears to be a wrong code bug for strictfp which affects RISCV.
*  [RISCV] wrong vector register alloc in vector instruction `#50157 <https://github.com/llvm/llvm-project/issues/50157>`_.  Appears to be a miscompile of vgather intrinsic, and may hint at a larger lurking issue.

VLEN=32 is known to be broken
=============================

This means that Zve32x and Zve32f are not supported.  Specific problems noted were around vscale computation and "scalable types" (unclear exact meaning to me).

It is not clear to me that anyone is ever going to care about this.  I'm not aware of any hardware existing or announced which would need this.

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

Punch List:

* `<https://github.com/llvm/llvm-project/issues/55447>`_ is specific to fixed width vectors 512 bits and larger.

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

Code Size
=========

There has been a general view that RISCV code size has significant room for improvement aired in recent LLVM RISC-V sync-up calls, but no specifics are currently known.


Performance (Minor)
-------------------

Things in this category are thought to be worth implementing individually, but likely individually minor in their performance impact.  Eventually, everything here should be filed as a LLVM issue, but these are my rough notes for the moment.  

Interesting cases from the LLVM issue tracker:

*  Unaligned read followed by bswap generates suboptimal code `#48314 <https://github.com/llvm/llvm-project/issues/48314>`_

   

Schedule VSETVL outside non-tail folded loops
=============================================

For main/epilogue style fixed length vectorization, the SETVL instruction is invariant across loop iterations.  We can hoist it into the preheader of the loop.

LSR Exit Test Formation
========================

Looking at a couple of examples, it looks like LSR is keeping around an extra induction variable just for performing the exit test.  We can probably fold it away, thus removing an increment from every iteration of simple vector loops.  

LoopVectorizer generating duplicate broadcast shuffles
======================================================

This is being fixed by the backend, but we should probably tweak LV to avoid anyways.

Duplicate IV for index vector
=============================

In a test which simply writes “i” to every element of a vector, we’re currently generating:

 %vec.ind = phi <4 x i32> [ <i32 0, i32 1, i32 2, i32 3>, %vector.ph ], [ %vec.ind.next, %vector.body ]
  %step.add = add <4 x i32> %vec.ind, <i32 4, i32 4, i32 4, i32 4>
  …
  %vec.ind.next = add <4 x i32> %vec.ind, <i32 8, i32 8, i32 8, i32 8>
  %2 = icmp eq i64 %index.next, %n.vec
  br i1 %2, label %middle.block, label %vector.body, !llvm.loop !8

And assembly:

    vadd.vi    v9, v8, 4
    addi    a5, a3, -16
    vse32.v    v8, (a5)
    vse32.v    v9, (a3)
    vadd.vi    v8, v8, 8
    addi    a4, a4, -8
    addi    a3, a3, 32
    bnez    a4, .LBB0_4
    beq    a1, a2, .LBB0_8

We can do better here by exploiting the implicit broadcast of scalar arguments.  If we put the constant id vector into a vector register, and add the broadcasted scalar index we get the same result vector.

Branch on inequality involving power of 2
=========================================

For the compare:
  %c = icmp ult i64 %a, 8
  br i1 %c, label %taken, label %untaken

We currently emit:
    li    a1, 7
    bltu    a1, a0, .LBB0_2

We could emit:
    slli    a0, a0, 3
    bnez    a0, .LBB1_2

This lengthens the critical path by one, but reduces register pressure.  This is probably worthwhile.

There are also many variations of this type of pattern if we decide this is worth spending time on.  
   
Optimizations for constant physregs (VLENB, X0)
===============================================

Noticed while investigating use of the PseodoReadVLENB intrinsic, and working on them as follow ons to `<https://reviews.llvm.org/D125552>`_, but these also apply to other constant registers.  At the moment, the two I can think of are X0, and VLENB but there might be others.

Punch list (most have tests in test/CodeGen/RISCV/vlenb.ll but not all):

* PeepholeOptimizer should eliminate redundant copies from constant physregs. (`<https://reviews.llvm.org/D125564`_)
* PeepholeOptimizer should eliminate redundant copies from unmodified physregs.  Looking at the code structure, we appear to already do all the required def tracking for NA copies, and just need to merge some code paths and add some tests.
* SelectionDAG does not appear to be CSEing READ_REGISTER from constant physreg.
* MachineLICM can hoist a COPY from constant physreg since there are no possible clobbers.
* forward copy propagation can forward constant physreg sources.
* Remat (during RegAllocGreedy) can trivially remat COPY from constant physreg.

X0 specific punch list:

* Regalloc should prefer constant physreg for unused defs.  (e.g. generalize 042a7a5f for e.g. volatile loads)  May be able to delete custom AArch64 handling too.

VLEN specific punch list:

* VLENB has a restricted range of possible values, port pseudo handling to generic property of physreg.
* Once all above done, remove PseudoReadVLENB.


Vaguely related follow on ideas:

* A VSETVLI a0, x0 <vtype> whose implicit VL and VTYPE defines are dead essentially just computes a fixed function of VLENB.  We could consider replacing the VSETVLI with a CSR read and a shift.  (Unclear whether this is profitable on real hardware.)


Optimizations for VSETVLI insertion
===================================

This is collection of pending items for improving VSETVLI placement.  In general, I think we're starting to hit the point of diminishing returns here, and some of the items noted below stand a good chance of being punted to later.

Optimization

* https://github.com/llvm/llvm-project/issues/55615 -- not really VSETVLI specific, looks like a bad interaction with fixed width vs scalable lowering
* We seem to end up with vsetvli which only toggle policy bits (tail and mask agnosticism).  There look to be oppurtunities here, but my first approach didn't work (https://reviews.llvm.org/D126967).  Pending discussion on approach.
* Missing DAGCombine rules:

  * Canonicalize AVLImm >= VLMax to VLMax register form.
  * GPR = vsetvli <value>, GPR folds to value when <value> less than VLMAX
  * If AVL=VLMAX, then TU is meaningless and can become TA.
  * If unmasked, then MU is meaningless and can become TU.

Vectorization
=============

Goal is to smoke out as many correctness problems around vectorization as possible, then enable some vectorization configuration (any configuration).

Configurations of Note

* -riscv-v-vector-bits-min=128 -- short fixed length
* -riscv-v-vector-bits-min=1024 -- long fixed length
* -scalable-vectorization=on -- scalable only, likely initial default
* -riscv-v-vector-bits-min=128 -scalable-vectorization=on -- both fixed and scalable enabled, very useful for smoking out cost model issues

Stages:

* Correctness - build code with vectorization flags enabled.
* Cost Model Completeness - No invalid costs seen when compiling (requires custom patch)

Workload Status:

* sqlite3 (many configs) -- stable, no invalid costs
* imagemagick -- build w/o link due to "missing files" (likely autoconf cross compile problem, using modified compiler to avoid CFLAGs issuess
* Clang stage2 build (many configs) -- successful build/link, no invalid costs, ran tests using llvm-lit + qemu-user no suspicious looking errors (I slightly screwed up my run, so there were errors, but none that looked to be anything other than user error - did not rerun due to length of run)
* llvm test-suite -- build/link w/ one error due to missing TCL in cross build (scalable vectorization only), ran all tests under qemu-user.  Several failures due to strip not recognizing cross compiled binaries, but nothing which looked suspicious.  Log output includes a bunch of Invalid costs for later consideration.
* spec2017 - all successfully cross compile, several generate link errors

Tuning

* Lots...
* Issues around epilogue vectorization w/VF > 16 (for fixed length vectors, i8 for VLEN >= 128, i16 for VLEN >= 256, etc..)
* Initial target assumes scalar epilogue loop, return to folding/epilogue vectorization in future.


Compressed Expansion for Alignment
==================================

If we have sequence of compressed instructions followed by an align directive, it would be better to uncompress the prior instructions instead of asserting nops for alignment.

This is analogous to the relaxation support on X86 for using larger instruction encodings for alignment in the integrated assembler.

This is of questionable value, but might be interesting around e.g. loop alignment.


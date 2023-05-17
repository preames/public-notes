-------------------------------------------------
Open Items in Scalar Codegen
-------------------------------------------------

.. contents::

Moving to latest specification
==============================

Punch list:

* F implies Zicsr (Finx probably does too)
* Zihpm, and Zicntr
* Various version number updates - thought to be non-semantic, but check!
* Double check CPU definitions - need to add zicsr, zifencei, zihpm, zicntr as appropriate
* Meaning of G, and canonical march string


Items in LLVM issue tracker
============================

*  [SelectionDAGISel] Mysteriously dropped chain on strict FP node. `#54617 <https://github.com/llvm/llvm-project/issues/54617>`_.  This appears to be a wrong code bug for strictfp which affects RISCV.
*  Unaligned read followed by bswap generates suboptimal code `#48314 <https://github.com/llvm/llvm-project/issues/48314>`_


Code Size
=========

There has been a general view that RISCV code size has significant room for improvement aired in recent LLVM RISC-V sync-up calls, but no specifics are currently known.

2022-07-11 - I spent some time last week glancing at usage of compressed instructions.  Main take away is that lack of linker optimization/relaxation support in LLD was really painful code size wise.  We should revisit once that support is complete, or evaluate using LD in the meantime.


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


Compressed Expansion for Alignment
==================================

If we have sequence of compressed instructions followed by an align directive, it would be better to uncompress the prior instructions instead of asserting nops for alignment.

This is analogous to the relaxation support on X86 for using larger instruction encodings for alignment in the integrated assembler.

This is of questionable value, but might be interesting around e.g. loop alignment.

Constant Materialization Gaps
=============================

For constant floats, we have a couple oppurtunities:

* LUI/SHL-by-32/FMV.D.X - Analogous to the LUI/FMV.W.X pattern recently implemented, but requires an extra shift.  This basically reduces to increasing the cost threshold by 1, and may be worth doing for doubles.  
* LI/FCVT.S.W - Create a small integer, and convert to half/single/double.  Note this is a convert, not a move.  For half, LUI/FMV.H.X may be preferrable.
* FLI.S/D - Likely to be optimal when Zfa is available.
* FLI + FNEG.S - Can be used to produce some negative floats and doubles.  LUI/FMV.W.X is likely better for floats and halfs, so this mostly applies to doubles.  FNEG.S can be used to toggle the sign bit on any float, so may be more broadly applicable as well.


Rematerialization of LUI/ADDI sequences
=======================================

Given an LUI/ADDI sequence - either from a constant or a relocation - we should be able to rematerialize either or both instructions if required to reduce register pressure during allocation.

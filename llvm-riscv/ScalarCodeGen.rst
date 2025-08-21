-------------------------------------------------
Open Items in Scalar Codegen for RISCV
-------------------------------------------------

.. contents::


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


Assorted Low Priority
=====================

PeepholeOptimizer should eliminate redundant copies from unmodified physregs.  Looking at the code structure, we appear to already do all the required def tracking for NA copies, and just need to merge some code paths and add some tests.  Need to be cautious of ABI copies - primarily profitability.

Should we set shouldAnalyzePhysregInMachineLoopInfo for MachineLICM specifically for FRM, VXRM, or other such configuration registers?

A VSETVLI a0, x0 <vtype> whose implicit VL and VTYPE defines are dead essentially just computes a fixed function of VLENB.  We could consider replacing the VSETVLI with a CSR read and a shift.  (Unclear whether this is profitable on real hardware.)


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


Rematerialization of LUI/ADDI sequences
=======================================

Given an LUI/ADDI sequence - either from a constant or a relocation - we should be able to rematerialize either or both instructions if required to reduce register pressure during allocation.


Register Pressure Reduction
===========================

Improvement to switch lowering - if generate an jump table for the labels, check to see if the result can be turned into a lookup table instead.  We're already paying the load cost.

Investigate simple improvements to ShrinkWrapping.

Consider firewalling cold call paths.

Define a fastcc variants where argument-0 and return don't require the same register and internalize aggressively - mostly helps LTO.

IPRA - Can we reduce need to spill some?

Prefer bnez (addi a0, a0, C) when doing so avoids the need for a immediate materialization and a0 has no other uses.

Prefer bnez (lshr a0, a0, XLen-1) for sign check, same logic as previous.  Also generalizes to bexti cases for any single bit check.

Use arithmetic more aggressively for select c, i32 C1, i32 C2 to avoid need for control flow.  (Doesn't really impact register pressure, may actually hurt.)

Aggressively duplicate (addi a0, x0, C) to users before register allocation OR itnegrate rematerialization into first CSR path.

Aggressively duplicate (addi a0, a0, C) when user is vector load or store to user to avoid long live ranges.  Or combine remat in first cSR + full remat.

Investigate full rematerialization.

Investigate negated compound branch thing reported 2024-11-24 on discourse.

In this simple example (https://godbolt.org/z/MW4WExYYP), why aren't we rescheduling to avoid the need for stack spills?



---------------
Notes on RISCV
---------------

This document is a collection of notes on the RISC-V architecture.  This is mostly to serve as a quick reference for me, as finding some of this in the specs is a bit challenging.

.. contents::

VLEN >= 32 (always) and VLEN >= 128 (for V extension)
-----------------------------------------------------

VLEN is determined by the Zvl32b, Zvl64b, Zvl128b, etc. extensions. V implies Zvl128b. Zve64* implies Zvl64b. Zve32* implies Zvl32b. VLEN can never be less than 32 with the currently defined extensions.

Additional clarification here:

"Note: Explicit use of the Zvl32b extension string is not required for any standard vector extension as they all effectively mandate at least this minimum, but the string can be useful when stating hardware capabilities."

Reviewing 18.2 and 18.3 confirms that none of the proposed vector variants allow VLEN < 32.

As a result, VLENB >= 4 (always), and VLENB >= 16 (for V extension).

ELEN <= 64
----------

While room is left for future expansion in the vector spec, current ELEN values encodeable in VTYPE max out at 64 bits.

vsetivli can not always encode VLMAX
------------------------------------

The five bit immediate field in vsetivli can encode a maximum value of 31.  For VLEN > 32, this means that VLMAX can not be represented as a constant even if the exact VLEN is known at compile time.

Odd gaps in vector ISA
----------------------

There are a number of odd gaps in the vector extension.  By "gap" I mean a case where the ISA appears to force common idioms to generate oddly complex or expensive code.  By "odd" I mean either seemingly inconsistent within the extension itself, or significantly worse that alternative vector ISAs (e.g. x86 or AArch64 SVE).  I haven't gone actively looking for these; they're simply examples of repeating patterns I've seen when looking at compiler generated assembly where there doesn't seem to be something "obvious" the compiler should have done instead.

No Zbb, Zbs (Basic bitmanip idioms) vector analogy extensions
=============================================================

The lack of Zbb and Zbs prevent the vectorization of many common bit manipulation idioms.  The code sequences to replicate e.g. bitreverse without a dedicated instruction are rather painfully expensive.  Being able to generate fast code for e.g. vredmax(ctlz(v)) has some interesting applications.

Impact: Major.  Practically speaking prevents vector usage for many common idioms.

No Zbc (carryless multiply) analogy extensions
==================================================

I haven't yet seen code which would benefit from a Zbc vector analogy, but I also don't much time on crypto and my understanding is that is the motivator for these.

Impact: ??

No SEW ignoring math ops
========================

When working with indexed load and stores, the index width and data width are often different.  For instance, say I want to add 8 bits of data from addresses `(9 x i +256)` off a common base.  The code sequence looks roughly like this::
  
  vsetvli x0, x0, e64, mf8, ta, ma
  vshl v2, v2, 3
  vadd v2, v2, 256
  vsetvli x0, x0, e8, m1, ta, ma
  vluxei64.v vd, (x1), v2, vm

Note that we're toggling vtype solely for the purpose of performing indexing in i64.  

If we had a version of the basic arithmetic ops which ignored SEW - or even better, a variant of the Zba instructions! - we could rewrite this sequence as::

  vshl64 v2, v2, 3
  vadd64 v2, v2, 256
  vluxei64.v vd, (x1), v2, vm

Or even better::

  vsh3add64 v2, v2, 256
  vluxei64.v vd, (x1), v2, vm

Note that 64 here comes from the native index width for a 64 bit machine.  We could either produce two 32/64 variants or a single ELEN paraterized variant.

Impact: minor, main benefit is reduced code size and fewer vtype changes

Another idea here might be to instead have an indexed load/store variant which implicitly scaled its index vector by the index type.  (That is, implicitly included a mutiplication of the index vector by the index width..)  That would give us code along the lines of the following::

  add x2, x1, 256
  vluxei64.v.scaled vd, (x2), v2, vm

No Cheap Mask Extend
====================

There does not appear to be a cheap zero or sign extend sequence to take a mask and produce e.g. an i32 vector.

The best sequence I see is::

  vmv.v.i vd, 0
  vmerge.vim vd, vd, 1, v0

How to fix:

* Allow EEW=1i on zext.vfN variants.  This covers extend to i8.
* Add zext.vf16,  zext.vf32, and zext.vf64 on the prior to get all SEW.
* Alternatively, add a dedicated mask extend op to SEW.

Impact: fairly minor, mostly some extra vector register pressure due to need for zero splat.

No Product Reduction
====================

There does not appear to be a way to lower an "llvm.vector.reduce.mul" or "llvm.vector.reduce.fmul" into a single reduction instruction.  Other reduction types are supported, but for some reason there's no 'vredprod', 'vfredoprod' or 'vfreduprod'.

Impact: minor, mostly me being completionist.

Non vrgather vector.reverse
===========================

Reversing the order of elements in a vector is a common operation.  On RISC-V today, this requires the use of a vrgather, and almost more importantly, a several instruction long sequence to materialize the index vector.  E,g, the following sequence reverses an i8 vector::

    csrr a0, vlenb
    srli a0, a0, 2
    addi a0, a0, -1
    vsetvli a1, zero, e16, mf2, ta, mu
    vid.v v9
    vrsub.vx v10, v9, a0
    vsetvli zero, zero, e8, mf4, ta, mu
    vrgatherei16.vv v9, v8, v10
    vmv1r.v v8, v9

Note that AArch64 provides an instruction for this.

Other ways to improve this sequence might be to variants of the SEW independent index arithmetic above, or providing a cheap way to get the VLMax splat.

Lack of e1 element type
=======================

For working with large bitvectors, having an element type of e1 would be helpful.  Today, we have the masked arithmetic ops, but because they're expected to only work on masks, they can't be combined with LMUL to work on more than one vreg of data.

Impact: minor, mostly a seeming inconsistency







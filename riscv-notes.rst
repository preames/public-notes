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

There are a number of odd gaps in the vector ISA.

No Cheap Mask Extend
====================

There does not appear to be a cheap zero or sign extend sequence to take a mask and produce e.g. an i32 vector.

The best sequence I see is::

  vmv.v.i v1, 0
  vadd v1, v1, 1, v0

How to fix:

* Allow EEW=1i on zext.vfN variants.  This covers extend to i8.
* Add zext.vf16,  zext.vf32, and zext.vf64 on the prior to get all SEW.
* Alternatively, add a dedicated mask extend op to SEW.

Impact: fairly minor, mostly some extra vector register pressure due to need for zero splat.

No Product Reduction
====================

There does not appear to be a way to lower an "llvm.vector.reduce.mul" or "llvm.vector.reduce.fmul" into a single reduction instruction.  Other reduction types are supported, but for some reason there's no 'vredprod', 'vfredoprod' or 'vfreduprod'.

Impact: minor, mostly me being completionist.

No Zba, Zbb, Zbc, or Zbd vector analogy extensions
==================================================

The lack of Zba is painful due to the lack of '[base + offset]' addressing in vector loads and stores.

Impact: widespread small increases in code size

The lack of Zbb and Zbd prevent the vectorization of many common bit manipulation idioms.  The code sequences to replicate e.g. bitreverse without a dedicated instruction are rather painfully expensive.

Impact: Major.  Practically speaking prevents vector usage for many common idioms.

I haven't yet seen code which would benefit from a Zbc vector analogy, but I also don't much time on crypto and my understanding is that is the motivator for these.

Impact: ??

No SEW ignoring math ops
========================

When working with indexed load and stores, the index width and data width are often different.  For instance, say I want to add 8 bits of data from a fixed offset off a list of pointers.  The code sequence looks roughly like this::
  
  vsetvli x0, x0, e64, mf8, ta, ma
  vshl v2, v2, 2
  vadd v2, v2, 256
  vsetvli x0, x0, e8, m1, ta, ma
  vluxei64.v vd, (x1), v2, vm

Note that we're toggling vtype solely for the purpose of performing indexing in i64.  

If we had a version of the basic arithmetic ops which ignored SEW - or even better, a variant of the Zba instructions! - we could rewrite this sequence as::

  vshl64 v2, v2, 2
  vadd64 v2, v2, 256
  vluxei64.v vd, (x1), v2, vm

Note that 64 here comes from the native index width for a 64 bit machine.  We could either produce two 32/64 variants or a single ELEN paraterized variant.

Impact: minor

Lack of e1 element type
=======================

For working with large bitvectors, having an element type of e1 would be helpful.  Today, we have the masked arithmetic ops, but because they're expected to only work on masks, they can't be combined with LMUL to work on more than one vreg of data.

Impact: minor, mostly a seeming inconsistency







------------------------------------------------------
Vector Idioms (nomenclature, and lowerings)
------------------------------------------------------

This page is a dumping ground for notes on various idiomatic patterns which show up in vector code, and thoughts on how each idiom can be implemented in RVV (RISC-V Vector).  The primary purpose of this page is to provide a common reference for nomenclature.  A secondary purpose is so that I can remember ideas I've come up with before.

.. contents::

Inserts and Extracts
====================


Element Insert & Extract
++++++++++++++++++++++++

Insert:

.. code::

   // With index = 0
   vmv.s.x vN, xM

   // When other elements are undefined
   vmv.v.i vN, <imm>
   vmv.v.x vN, xM
   vfmv.v.f vN, fM

   // Via vslideup
   vmv.s.x vTMP, xN
   vsetivli zero, <imm+1>, <vtype>
   vslideup.vi vN, vTMP, imm

   // Via vmerge
   // populate v0 mask, usually via LUI/ADDI + vmv.s.x
   vmerge.vxm vN, vN, xM, v0

Extract:

.. code::

   vslidedown.vi vTMP, vN, imm
   vmv.x.s xN, VTMP
   OR
   vfmv.f.s FN, VTMP

LMUL Sensitivity
  Note that vmerge, vslideup, and vslidedown are likely to be O(LMUL) in cost.  As a result, these operations scale linearly with the vector LMUL.  If the index being inserted/extracted is known to be in a smaller LMUL prefix or (for VLS code) a specific sub-register, using a smaller LMUL for the insert or extract is very likely profitable.

Non-Immediate Index
  All of the examples given are for immediate indices because these are by far the most common in practice.  You can write .vx forms of most of these, but there's no easy VLS or prefix optimizations available.

Mask Creation and Manipulations
===============================

Small Constant Masks (VL < ELEN)
++++++++++++++++++++++++++++++++

For masks w/VL < ELEN, prefer creation of a scalar constant and insert
into the low element of an ELEN vector for most cases.  e.g. 

.. code::

   // VL=4
   vsetvli t0, x0, e8, m1, ta, ma
   li t0, 0b1100
   vmv.v.i v0, 0b0111

   // VL=8
   vsetvli t0, x0, e8, m1, ta, ma
   li t0, 0b11100111
   vmv.v.x v0, t0

Repeating Masks
+++++++++++++++

For a mask with a repeating sequence where the sequence length is a multiple
of 8, use vmv.v.x or vmv.v.i and splat the pattern across all lanes of an m1
vector.

.. code::

   // Even element mask
   vsetvli t0, x0, e8, m1, ta, ma
   li t0, 0b01010101
   vmv.v.x v0, t0

   // Odd element mask
   vsetvli t0, x0, e8, m1, ta, ma
   li t0, 0b10101010
   vmv.v.x v0, t0

   // Every 8th element
   vsetvli t0, x0, e8, m1, ta, ma
   vmv.v.x v0, 0b0001

Arithmetic Tricks
+++++++++++++++++

There are many common arithmetic idioms for creating bit patterns which involve add/sub. (e.g. see Hacker's Delight)  Without an add/sub instruction which operates at full mask width, these can be hard to adapt.  For masks less than ELEN, element wise operations can be used.  For masks greater than ELEN, add and subtract can be emulated at reasonable cost (see below) for 128b and (maybe) e256.  Emulating for fully generic VLA sequences is possible, but quite expensive.

Shuffles (Rearranging Elements)
===============================

We have a bunch of known shuffles with lowerings which are better than general vrgather.vv.  A few that have native hardware support (see ISA manual):

* Vector Select
* Slide Up and Down

And a couple of generally useful tactics:

* Split and merge (for two source operand shuffles)
* Split at VREG boundary (assumes VLS)
* e16 constants with vrgatherei16.vv (all fixed length vectors)
* Emulated vrgather.ei4 for VL<=16

Splat from Scalar
+++++++++++++++++

.. code::

   vmv.v.i v1, <imm>
   OR
   vmv.v.x v1, t0
   OR
   vfmv.v.f v1, f0

Splat from Vector Element (SEW<=64)
+++++++++++++++++++++++++++++++++++

The canonical way to do this operation is:

.. code::

   vrgather.vi v1, v1, <imm>
   vrgather.vx v1, v1, t0

 Prefer the VI form if possible.

Repeating Subvector (i.e. Splat SEW>64)
+++++++++++++++++++++++++++++++++++++++

Assume the subvector you wish to splat is in the low elements of the vector, and that the size is a power of two.

For sizeof(subvec) < VLENB:

.. code::

   // For VLA
   vid v1
   vand.vi v1, v1, <imm>
   vrgather.vv v3, v2, v1

   // For VLS
   vslideup.vi v3, v2, <imm>
   // repeat O(log VLENB) as needed, or use above

For sizeof(subvec) >= VLENB, use whole register moves to "splat" across as many VREGs as required.

Vector Rotate
+++++++++++++

.. code::

   vslidedown.vi v1, v2, <imm>
   vslideup.vi v1, v2, <imm2>

Vector Reverse
++++++++++++++

For m1, the naive strategy works just fine.

.. code::

  vid.v v1
  vrsub.vx/i v1, VL
  vrgather.vv vd, vsrc, v1

  // For VLA, can come from vsetvli in tail folded loop
  // OR e.g.
  vid.v v1
  csrr t0, vlenb
  slli t0, log_2(SEW/8)

  // For VLS (i.e. exact VLEN is known) then VL is a constant

For m2 and above, we want to avoid an O(LMUL^2) vrgather.vv.  Our basic strategy will be:

* Slide the vector up to fill the register group (leaving space at bottom)
* Use whole register moves to swap VREGS
* Perform one m1 reverse per VREG.
* vmerge with the destination (or -1) if tail contents are defined

The slide step can be skipped if VL=VLMAX.  If VL is a multiple of VLMAX for m1, then the slide can be skipped and the whole register moves adjusted slightly.  The vmerge can be skipped in the (very common) case the tail elements are undefined.

Vector Compress
+++++++++++++++

A vector compress operation returns a vector where every element in the source appears at most once, a location at or strictly less than it's position in the original vector.  Elements can be discarded.  See the `vcompress` instruction definition in the ISA manual.

vcompress scales better with LMUL than a general vrgather.vv, and at least the SpaceMit X60, has higher throughput even at m1. It also has the advantage of requiring smaller vector constants at one bit per element as opposed to vrgather which is a minimum of 8 bits per element. The downside to using vcompress is that we can't fold a vselect into it, as there is no masked vcompress variant.  This can cause increased register pressure in some cases.

Note that there are many sub-cases which can be more efficiently lowered.  Examples:

* deinterleave(2)
* Many VL=2 cases can be done with a masked vslide

Vector Decompress
+++++++++++++++++

See the `vdecompress` discussion in the ISA manual.  If the mask is constant, the `viota` is just a vrgather index mask constant.  

Sheep and Goats
+++++++++++++++

The sheep-and-goals (SAG) operator is from "Hacker's Delight".  It performs a stable sort of the elements in a vector based on a binary key.  Said differently, it groups all "sheep" (mask bit set) before all "goats" (mask bit unset).

.. code::

   vcompress.vm vd, vs1, v0
   vcpop.m t0, v0
   vmnot v0, v0
   vcompress.vm vtmp, vs1, v0   
   vslideup.vx vd, vtmp, t0

Note that if the population count of the mask is known (e.g. it's a constant), the vcpop.m can be skipped and vslideup.vi can be used.

Interleave (a.k.a. zip)
+++++++++++++++++++++++

Given two input vectors of the form::
  V1 = a_0, a_1, ..

  V2 = b_0, b_1, ..

Then `interleave(2)` produces::
  a_0, b_0, a_1, b_1, ...

.. code::

   // (SEW <= 32 only)
   vwaddu.vv vtmp, vs1, vs2
   li a0, -1                        
   vwmaccu.vx vtmp, a0, vs2
   
   // (SEW <= 32 only, with zvbb)
   vwsll.vi vd, vs1, sizeof(SEW)
   vwadd.wv vd, vd, vs2

   // (SEW = 64 using split shuffle assuming m1 inputs)
   vmv1r vd_0, vs2
   vslideup.vi vd_0, vs1, VLMAX/2
   vmv1r vd_1, vs2
   vslidedown.vi vd_0, vs1, VLMAX/2
   vle16.v vtmp, (a0) // load [0, VLMAX/2, 1, VLMAX/2+1] shuffle index vector
   vrgatherei16.vv vd_0, vd_0, vtmp
   vrgatherei16.vv vd_1, vd_1, vtmp

   // (SEW = 64 using m2 shuffle)
   vle16.v vtmp, (a0) // load [0, VLMAX/2, 1, VLMAX/2+1] shuffle index vector
   vd = {vs0, vs1} // may involve whole register moves
   vrgatherei16.vv vd, vd, vtmp

`interleave(N)` is defined in an analogous manner, but with a corresponding larger number of input registers.

NOTE: This is describing the standalone shuffle.  If this operation is followed by a store, consider a segment store.
   
Element Spread(N)
+++++++++++++++++

See also: decompress, element repeat, and interleave

Given two input vectors of the form::
  V1 = a_0, a_1, ..

Then `spread(2)` produces::
  a_0, undef, a_1, undef, ...

Then `spread(3)` produces::
  a_0, undef, undef, a_1, ...

For source SEW<=32, and Factor=2:

.. code::
   
   vzext.vf2 vd, vs1
   OR
   vwadd.vx vd, vs1, zero

Otherwise, use vrgather.vv.  However, this pattern can be split into a linear number of m1 shuffles even without knowing the exact VLEN boundary, so this can be done in O(LMUL) work if Factor is a power-of-two.

Element Repeat(N)
+++++++++++++++++

Given input vector of the form::
  V1 = a_0, a_1, ..

Then `repeat(2)` produces::
  a_0, a_0, a_1, a_1, ...

Then `repeat(3)` produces::
  a_0, a_0, a_0, a_1, a_1, a_1, ...

Approaches:

* See interleave(2) strategies with V1 being both input operands.
* Spread + masked slide (particularly for SEW<=32, and N=2)
* Larger SEW vrgather.vv for small sequences

   
Deinterleave (a.k.a. Unzip)
+++++++++++++++++++++++++++

There are two common variants of deinterleave.  The difference between them basically comes down to whether you want some subset of the lanes in individual registers, or if you want all of the lanes in a register (group) but reordered.  The former produces a result which is 1/Factor of the input size, the later produces an output equal to the input size.

Given an input vector of the form::
  V1 = a_0, a_1, ..

Then the full `deinterleave(2)` produces::
  a_0, a_2, a_4, ..., a_1, a_3, a_5, ...

And `deinterleave(2,0)` produces::
  a_0, a_2, a_4, ...

Here's sequences for a `deinterleave(2,Offset)`.

.. code::

   // SEW <= 32 only (preferred sequence)
   vnsrl.vi v2, v2, 0 // offset=0
   vtmp = vnsrl.wi vs1, sizeof(SEW) // offset=1

   vid.v v1
   vsrl.vi v1, v1, 1
   vrgather.vv v, v2, v1

   li t0, 0b01010101
   vmv.v.x v1, t0
   vcompress.vv v3, v2, v0.t

   // SEW = 64, result LMUL=m1  -- note that fractional LMUL ill defined for e64
   vsetvli a0, zero, e64, m1, ta, mu
   li t0, 0b10101010
   vmv.v.x v0, t0
   vslideup.vi v9, v8, 1, v0.t
   vle16 v2, (a0) /// 0, 2, 4, ... 1, 3, 5, 7
   vrgather.vv v8, v9, v2

   // Note that the first three instructions after the vsetvli form a zipeven
   // and the later two form a `deinterleave(2)` full shuffle.


Notes:

* The m1 sequence relies on the observation that only even elements are used from both registers in the m2 source register group, and that all of the required elements can fit within a m1 register with the right slide applied.
* Note that the index vector described is a pain point with this sequence.  The sequence is shown with a load from constant pool, but for a VLA use case, an alternate sequence would be required.  I believe that can be done in 4-5 m1 instructions, but I haven't bothered to quite work it out as the cases I've looked at in practice all have fixed VLs. 
* For e64, m2 and m4, the same trick from m1 can be applied pairwise within the vector register group.  (Note that m8 is ill defined as described above.)
   
Here's the code for the full `deinterleave(2)` shuffle:

.. code::

   // (SEW <= 32 only)
   vtmp = vnsrl.wi vs1, sizeof(SEW)
   vtmp = vnsrl.wi vs1, 0
   vslideup.vi vd, vtmp, VL/2

   // SEW = 64, LMUL = m1
   vle16 v2, (a0) /// 0, 2, 4, ... 1, 3, 5, 7
   vrgather.vv vd, vs1, v2

   // SEW = 64, LMUL > m1
   v0 = {1010..}
   vcompress.vm vd, vs1, v0
   vmnot v0, v0 // {0101..}
   vcompress.vm vtmp, vs1, v0
   vslideup.vi vd, vtmp, VL/2

   // SEW = 64, LMUL > m1 (preferred)
   // This formation allows the splitting as above, which means this is O(2*LMUL)
   concat_vector(deinterleave(2,0), deinterleave(2,0))

You can also extend these approaches to more than two alternating sub-series.

   
Zip Even & Zip Odd
++++++++++++++++++

Given two input vectors of the form::
  V1 = a_0, a_1, ..

  V2 = b_0, b_1, ..

Then `zip_even` produces::
  a_0, b_0, a_2, b_2, ..

Then `zip_odd` produces::
  a_1, b_1, a_3, b_3, ..

.. code::

   // zip_even
   li t0, 0b10101010
   vmv.v.x v0, t0
   vslideup.vi   vs1, vs2, 1, v0.t

   // 4 instructions SEW < 32
   vs1 = deinterleave2(vs1, 0)
   vs2 = deinterleave2(vs2, 0)
   vd = interleave(vs1, vs2)

   // zip_odd
   li t0, 0b01010101
   vmv.v.x v0, t0
   vslidedown.vi vs2, vs1, 1, v0.t

   // 4 instructions SEW < 32
   vs1 = deinterleave2(vs1, 1)
   vs2 = deinterleave2(vs2, 1)
   vd = interleave(vs1, vs2)


A few special cases:

* With fixed length vectors < XLEN elements, the mask creation sequences above can be replaced with LUI/ADDI + vmv.s.x which is likely strictly preferable.
* VL=1 zipeven is just an unmasked slideup.
* If preceeded by a load, or followed by a store, the deinterleave/interleave scheme above may be folded into a segment load or store.
   
Adjacent Element Swap
+++++++++++++++++++++

Given an input vector of the form::
  a_0, a_1, a_2, a_3, ..

Produce::
  a_1, a_0, a_3, a_2, ..

.. code::

   vtmp1 = deinterleave2(V1, 0)
   vtmp2 = deinterleave2(V1, 1)
   vd = interleave2(vtmp1, vtmp2)

   // populate v0 = 101010...
   vslide1up.vx vtmp, vsrc, zero
   vslide1down.vx vtmp, vsrc, zero, v0

   // SEW < 64 with zvbb
   Toggle SEW=SrcSEW*2
   vror.vi vsrc, vsrc, sizeof(sew)

   vslide1down.vx vtmp, vsrc, zero
   vzipeven.vv vtmp, vsrc, vtmp

Element Wise Operations
=======================

UInt4 and SInt4 Unpack
++++++++++++++++++++++

Nibble data is relatively common.  Specific use cases:

* Quantized ML/AI
* Small vrgather.vv index lists (for VL<=16 shuffles)

UInt4 zero extend to e8::

  vsrl.vi v2, v1, 4
  vand.vi v1, v1, 15
  v1 = interleave(v1, v2)

SInt4 sign extend to e8::

  vsrl.vi v2, v1, 4
  vand.vi v1, v1, 15
  vsll.vi v1, v1, 4
  vsll.vi v2, v2, 4
  vsra.vi v1, v1, 4
  vsra.vi v2, v2, 4
  v1 = interleave(v1, v2)

  Note: You might be able to do the sign extend via subtraction in the case above

When unpacking int4, note that if *order* is unimportant, then the interleave can be replaced with a simple slideup instead.  If the resulting order *is* important - for instance, a vrgather.vv index vector - consider where the source data can be stored in an inverted order to allow the vslideup trick.

Alternatively, if the next step is done element wise, the interleave can be deferred by performing the element wise operation twice.

Element Wise Absolute Difference
++++++++++++++++++++++++++++++++

Unsigned (ABDU)::

  vminu.vv v10, v8, v9
  vmaxu.vv v8, v8, v9
  vsub.vv v8, v8, v10

Element Wise Bit Rotate
+++++++++++++++++++++++

Approaches:

* vror.vi w/zvbb
* vsll, vsrl and vor

e128 Vector Arithmetic
++++++++++++++++++++++

For add (subtract), the following strategy can be used:

* vmadc (vsbc), then mask out odd lanes via vmand
* left shift carry mask by one bit
* vadc (vsbc)

Alternatively, you can shift the source vector down by one element, and then the result of vadc (vsbc) up by one to avoid the (possibly expensive) mask shift.

The basic idea can be extended to e256, e512, etc... with more rounds

Reduction Variants
==================


Dot Product (Integer)
+++++++++++++++++++++

Heavily used in linear algebra, but also a useful building block for other idioms described here.  Key characteristics of a given (integer) dotproduct are the source SEW, destination SEW, and intermediate extend kind (signed vs unsigned).

Same Width SEW=8,16,32,64::

  vmul.vv v1, v1, v2
  vmv.v.x v3, zero
  vredsum.vs v3, v1, v3
  vmv.x.s a0, v3

Mixed Width AccumSEW>SrcSEW::

  // Toggle SEW=SrcSEW
  vwmul[u].vv v1, v1, v2
  // Toggle SEW=SrcSEW*2
  vmv.v.x v3, zero
  vredsum.vs v3, v1, v3
  vmv.x.s a0, v3
  zext.h/w/b a0, a0

  (The basic idea on the above is to do the multiply in the narrowest legal SEW, and delay promotion until after the reduction if possible.)

AccumSEW=32, SrcSEW=8 (w/ the `proposed Zvqdotq extension <https://github.com/riscv/riscv-dot-product/>`_)::

  vmv.v.x v3, zero
  vmv.v.x v4, zero
  vqdot.vv v3, v1, v2
  vredsum.vs v3, v3, v4
  vmv.x.s a0, v3
  
UInt4 Source::

  // Simple, but slightly slower
  v1 = unpack_uint4(v1) // DestLMUL=SrcLMUL*2
  v2 = unpack_uint4(v2) // DestLMUL=SrcLMUL*2
  a0 = dotproduct(v1, v2)

  // Exploit associativity
  vsrl.vi v3, v1, 4
  vand.vi v4, v1, 15
  vsrl.vi v1, v2, 4
  vand.vi v2, v2, 15
  vmul.vv v1, v1, v3
  vmul.vv v2, v2, v4
  // Toggle SEW=16
  vwadd.vv v2, v2, v1
  vmv.v.x v3, zero
  vredsum.vs v3, v1, v3
  vmv.x.s a0, v3
  zext.h/w/b a0, a0

  // As above, but with slides
  vsrl.vi v3, v1, 4
  vand.vi v4, v1, 15
  vsrl.vi v1, v2, 4
  vand.vi v2, v2, 15
  vslideup v1, v3, VL/2
  vslideup v2, v4, VL/2
  vmul.vv v1, v1, v2
  // Toggle SEW=16
  vmv.v.x v3, zero
  vwredsum.vs v3, v1, v3
  vmv.x.s a0, v3
  zext.h/w/b a0, a0

SInt4 Source::

  // Analogous to Int4 case, but add the sign extend step

  // TBD - There may also be a possible left shifted formulation
  // usuable with a couple less shifts on short vectors.  Not yet explored.

Sum of Squares
++++++++++++++

Shows up in e.g. mean squared error, geometric mean, vector magnitude/length, cosine similiarity.  Very common in vector distance or error metrics.

This is just a dotproduct of an argument with itself.  Usually, with a wider destination type than source and an unsigned extend (but not always).

Packed Horizontal Add (Pairwise) Accumulate
+++++++++++++++++++++++++++++++++++++++++++

a[i] += b[i*2] + b[i*2 + 1]::

  // Note that deinterleave2 is vnsrl SrcSEW <= 32 (i.e. all possible ones)
  v4 = deinteleave2(v2, 0)
  v5 = deinteleave2(v2, 1)
  // Toggle SEW=SrcSEW*2
  vwadd.vv v4, v4, v5
  // Extend if SrcSEW*2 != DstSEW
  vadd.vv v1, v4, v1

If this operation follows a load, consider a segment load followed by a widening add.

Packed Horizontal Add (Quads) Accumulate
+++++++++++++++++++++++++++++++++++++++++++

a[i] += b[i*2] + b[i*2 + 1] + b[i*2 + 2] + b[i*2 + 3]::
  
  // Option A
  v4 = deinteleave4(v2, 0)
  v5 = deinteleave4(v2, 1)
  v6 = deinteleave4(v2, 1)
  v7 = deinteleave4(v2, 1)
  // Toggle SEW=SrcSEW*2
  vwadd.vv v4, v4, v5
  vwadd.vv v6, v6, v7
  vadd.vv v4, v4, v6
  // Extend if SrcSEW*2 != DstSEW
  vadd.vv v1, v4, v1

  // Option B
  v2 = packed_horzontal_add_pairs(v2) @ SrcSEW -> SrcSEW*2
  v2 = packed_horzontal_add_pairs(v2) @ SrcSEW*2 -> SrcSEW*4

  // Option C - A slightly optimized version of 'B'
  v2 = packed_horizontal_add_pairs(v2) @ SrcSEW -> SrcSEW*2
  v4 = deinterleave2(v2, 0) @ SrcSEW * 2
  v5 = deinterleave2(v2, 1) @ SrcSEW * 2
  vadd.vv v2, v4, v5 # NOT vwadd due to excess bits
  vwadd.wv v1, v1, v2 # accumulate

AccumSEW=32, SrcSEW=8 (w/ the `proposed Zvqdotq extension <https://github.com/riscv/riscv-dot-product/>`_)::

  lui/addi a0, <1,1,1,1>
  vmv.v.x v3, zero
  vqdot.vx v3, v1, a0


Packed Horizontal Add (Octo) Accumulate
++++++++++++++++++++++++++++++++++++++++

See the same ideas as applied for options A-C for the quad case above.


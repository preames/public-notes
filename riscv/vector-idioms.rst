------------------------------------------------------
Vector Idioms (nomenclature, and lowerings)
------------------------------------------------------

This page is a dumping ground for notes on various idiomatic patterns which show up in vector code, and thoughts on how each idiom can be implemented in RVV (RISC-V Vector).  The primary purpose of this page is to provide a common reference for nomenclature.  A secondary purpose is so that I can remember ideas I've come up with before.



Shuffles (Rearranging Elements)
===============================

We have a bunch of known shuffles with lowerings which are better than general vrgather.  Eventually, we need to write all these down somewhere, but for now, here's simple a list of cases we can handle.  Check the output of clang, or ask around for details.

* Vector Select
* Slide Up and Down
* Element Bit Rotate (Reverse)
* Vector Rotate
* e256 w/VLA
* Compress

And a couple of generally useful tactics:

* Split and merge (for two source operand shuffles)
* Split at VREG boundary (assumes VLS)
* e16 constants with vrgather.ei16 (all fixed length vectors)
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

For sizeof(subvec) < VLENB, use vslideup.vi to produce a 2x vector.  Repeat until next item applies.

For sizeof(subvec) >= VLENB, use whole register moves to "splat" across as many VREGs as required.

Vector Reverse
++++++++++++++

For m1, the naive strategy works just fine.

.. code:: 

  // VLA
  vid v1
  csrr t0, vlenb
  slli t0, log_2(SEW/8)
  vrsub v1, t0
  vrgather.vv vd, vsrc, v1

  // If exact VLEN is known, VLMAX is constant
  vid v1
  vrsub v1, VLMAX
  vrgather.vv vd, vsrc, v1

For m2 and above, we want to avoid an O(LMUL^2) vrgather.vv.  Our basic strategy will be:

* Slide the vector up to fill the register group (leaving space at bottom)
* Use whole register moves to swap VREGS
* Perform one m1 reverse per VREG.
* vmerge with the destination (or -1) if tail contents are defined

The slide step can be skipped if VL=VLMAX.  If VL is a multiple of VLMAX for m1, then the slide can be skipped and the whole register moves adjusted slightly.  The vmerge can be skipped in the (very common) case the tail elements are undefined.

Vector Compress
+++++++++++++++

A vector compress operation returns a vector where every element in the source appears at most once, a location at or strictly less than it's position in the original vector.  Elements can be discarded.  See the `vcompress` instruction definition in the ISA manual.

vcompress scales better with LMUL than a general vrgather, and at least the SpaceMit X60, has higher throughput even at m1. It also has the advantage of requiring smaller vector constants at one bit per element as opposed to vrgather which is a minimum of 8 bits per element. The downside to using vcompress is that we can't fold a vselect into it, as there is no masked vcompress variant.  This can cause increased register pressure in some cases.

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

   vcompress vd, vs1, v0
   vcpop.m t0, v0
   vmnot v0, v0
   vcompress vtmp, vs1, v0   
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
   
   // (SEW <= 32 only, assuming zvbb)
   vwsll vd, vs1, sizeof(SEW)
   vwadd vd, vd, vs2

   // (SEW = 64 using split shuffle assuming m1 inputs)
   vmv1r vd_0, vs2
   vslideup.vi vd_0, vs1, VLMAX/2
   vmv1r vd_1, vs2
   vslidedown.vi vd_0, vs1, VLMAX/2
   vlse16.v vtmp, (a0) // load [0, VLMAX/2, 1, VLMAX/2+1] shuffle index vector
   vrgather.ei16 vd_0, vd_0, vtmp
   vrgather.ei16 vd_1, vd_1, vtmp

   // (SEW = 64 using m2 shuffle)
   vlse16.v vtmp, (a0) // load [0, VLMAX/2, 1, VLMAX/2+1] shuffle index vector
   vd = {vs0, vs1} // may involve whole register moves
   vrgather.ei16 vd, vd, vtmp

`interleave(N)` is defined in an analogous manner, but with a corresponding larger number of input registers.
   
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

* See interleave(2) stratagies with V1 being both input operands.
* Spread + masked slide (particularly for SEW<=32, and N=2)
* Larger SEW vrgather for small sequences

   
Deinterleave (a.k.a. Unzip)
+++++++++++++++++++++++++++

Given an input vector of the form::
  V1 = a_0, a_1, ..

Then `deinterleave(2)` produces::
  a_0, a_2, a_4, ..., a_1, a_3, a_5, ...

(With variants that want the two sub-series in the same register, or two different output registers.)

.. code::

   // (SEW <= 32 only, assuming zvbb)
   vtmp = vnsrl vs1, sizeof(SEW)
   vtmp = vnsrl vs1, 0
   vslideup.vi vd, vtmp, VL/2

   // (SEW = 64)
   v0 = {1010..}
   vcompress vd, vs1, v0
   vmnot v0, v0 // {0101..}
   vcompress vtmp, vs1, v0
   vslideup.vi vd, vtmp, VL/2

If you only need one of the sub-series, the above simplify in the obvious ways.

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
   vid vtmp
   vand.vi vtmp, vtmp, 1
   vmseq.vi v0, vtmp, 0
   vmv1r vd, vs1
   vslideup.vi   vd, vs2, 1, v0

   // zip_odd
   vid vtmp
   vand.vi vtmp, vtmp, 1
   vmseq.vi v0, vtmp, 0
   vmv1r vd, vs2
   vslideup.vi   vd, vs1, 1, v0


Element Wise Operations
=======================

UInt4 and SInt4 Unpack
++++++++++++++++++++++

Nibble data is relatively common.  Specific use cases:

* Quantized ML/AI
* Small vrgather index lists (for VL<=16 shuffles)

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

When unpacking int4, note that if *order* is unimportant, then the interleave can be replaced with a simple slideup instead.  If the resulting order *is* important - for instance, a vrgather index vector - consider where the source data can be stored in an inverted order to allow the vslideup trick.

Alternatively, if the next step is done element wise, the interleave can be deferred by performing the element wise operation twice.

Element Wise Absolute Difference
++++++++++++++++++++++++++++++++

Unsigned (ABDU)::

  vminu.vv v10, v8, v9
  vmaxu.vv v8, v8, v9
  vsub.vv v8, v8, v10


Reduction Variants
==================


Dot Product (Integer)
+++++++++++++++++++++

Heavily used in linear algebra, but also a useful building block for other idioms described here.  Key characteristics of a given (integer) dotproduct are the source SEW, destination SEW, and intermediate extend kind (signed vs unsigned).

Same Width SEW=8,16,32,64::

  vmul[u].vv v1, v1, v2
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
  vmul[u].vv v1, v1, v3
  vmul[u].vv v2, v2, v4
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
  vmul[u].vv v1, v1, v2
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
  v2 = packed_horzontal_add_pairs(v2) @ SrcSEW -> SrcSEW*2
  v4 = deinterleave2(v2, 0) @ SrcSEW * 2
  v5 = deinterleave2(v2, 1) @ SrcSEW * 2
  vadd v2, v4, v5 # NOT vwadd due to excess bits
  vwadd.wv v1, v1, v2 # accumulate

Packed Horizontal Add (Octo) Accumulate
++++++++++++++++++++++++++++++++++++++++

See the same ideas as applied for options A-C for the quad case above.


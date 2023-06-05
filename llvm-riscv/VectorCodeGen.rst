-------------------------------------------------
Open Items in Vector Codegen for RISCV
-------------------------------------------------

Note, vectorization issues are tracked distinctly from vector codegen quality issues.  They're obviously heavily inter-related.

See also vector-codegen.ll for individual test cases and descriptive comments.

.. contents::

Functional
==========

Skiming through the issue tracker for "riscv", I see a couple of concerning looking items.

*  [RISCV] wrong vector register alloc in vector instruction `#50157 <https://github.com/llvm/llvm-project/issues/50157>`_.  Appears to be a miscompile of vgather intrinsic, and may hint at a larger lurking issue.

Zvbb Codegen
============

MC support for zvbb was added in https://reviews.llvm.org/D148483.  This extension adds a number of generically useful vector bitmanip instructions.  We should implement codegen pattern matching for it, and then ensure the cost model is adjusted such that LV and SLP benefit from the capability.

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

Segment Loads and Stores
========================

We're currently generating 2-wise segment load and stores.  See https://reviews.llvm.org/D145085.

Particularly for fixed length vectors, there's both room to support up-to-8 interleave and deinterleave, and lots of room to improve codegeneration for them respectively.

Expansion via General loop scalarization
========================================

For scalable vectors, we _can_ scalarize, but not via unrolling.  Instead, we must generate a loop. This is not possible in SelectionDAG (which is not allowed to modify the CFG).  Eventually, we need a good answer to this as opposed to just relying on LV to never generate the illegal constructs.

Intrinsic Costing
=================

We are missing a bunch of intrinsic costs for vectorized intrinsic calls.  This results - due to the inability to scalarize - in invalid costs being returned and thus vectorization not triggering.  I've added floating point rounding and integer intrinsics, but we need to cost the remainder.

Constant Materialization of Large Constants
===========================================

Current constant materialization for large constant vectors leaves a bit to be desired.  Here's a list of cases which might be interesting to improve:

* Forming vector splats for constant fixed length vectors which can't be folded into operand (e.g. for a store).  Currently, we emit constant pool loads where-as splatting an etype constant would be significantly better.  Shows up in idiomatic vectorized constant memset patterns.
* Forming vector splats where the element size is larger than the largest natively supported element.  (e.g. splat of a 128b value with largest etype being e64.)  Shows up in vector crypto, and probably any i128 math lib.  One strategy is to splat two vectors (one for high, one for low), and then mask them together.  Can probably generalize for a whole sequence of vectors.
* sizeof(vector) < ELEN.  These could be scalar mat + a vector insert at ELEN etype.  Not always profitable depending on required constant mat cost on scalar side.
* Forming 128b constants with "cheap" i64 halfs.  We don't want to always use 64 bit scalar + insert idioms since general 64 bit constants are expensive, but for cases where we can materialize the halfs in one or two instructions, it's probably better than a constant pool load.  (Can also use two splats + merge idiom.)
* Few common bytes.  If a constant has only a handful of unique bytes, then using a smaller constant (made up only of those bytes) and a vrgather (with a new constant index vector) to shuffle bytes is feasible.  Only profitable if a) vrgather is cheap enough and b) cost of two new constants is low.
* Small constants values in large etype.  Can use vsext and vzext variants to reduce size of constant being materialized.  Combines with tricks (e.g. move from scalar) to make vectors with all lanes near zero significantly cheaper.  (e.g. <i32 -1, i32 0, i32 2, i32 1>, is sext <i8 -1, i8 0, i8 2, i8 1> to <4 x i32>, and thus a 32 bit constant + the extend cost)
* All the usual arithmetic tricks apply.  Probably only profitable on non-splat vectors, but could be useful for e.g. reducing number of active bits.

Note that many of these patterns aren't really constant specific, they're more build vector idioms appiled to constants.

Scalable Vectors in KnownBits (and friends)
===========================================

Scalable vectors had not been plumbed through known bits, demanded bits, or most of the other ValueTracking-esq routines.

I have a series of patches starting with https://reviews.llvm.org/D136470 (see the review stack) which adds basic lane wise reasoning.  Most of these have landed.  Once all of these land, there's a couple small todos:

* Add support for step_vector to all the routines touched above
* Complete the audit of all the target hooks and remove the bailouts one by one
* Fix the hexagon legalization problem seen in https://reviews.llvm.org/D137140 and add implicit truncation in SDAG's KnownBits
* Add splat_vector base cases (analogous to constant base cases) to all of the isKnownX routines in ValueTracking and SDAG.  This is more generic extension to handle shufflevector than anything else.
* Revisit insertelement handling, and be less conservative where possible.

Longer term, my last comment on that review describes the direction.  It's copied here for ease of reference.

For the record, let me sketch out where I think this might be going long term.

For scalable vectors, we have a couple of idiomatic patterns for representing demanded elements.

The first is a splat - which this patch nicely handles by letting us do lane independent reasoning on scalable vectors. This covers a majority of the cases I've noticed so far, and is thus highly useful to have in tree as we figure out next steps.

The second is sub_vector insert/extract. This comes up naturally in SDAG due to the way we lower fixed length vectors on RISCV (and, I think, ARM SVE.) This requires tracking a prefix of the demanded bits corresponding to the fixed vector size, and then a single bit smeared across remaining (unknown number of) lanes.

We could pick the prefix length in one of two ways:

* From the fixed vector being inserted or extracted.
* From the minimum known vector register size. This is more natural in DAG; at the IR layer, this requires combining the minimum vector length of a type which the minimum vscale_range value.

The third is scalar insert/extract. For indices under the minimum vector size, this reduces the former case. I don't yet know how common various runtime indices we can't prove in bounds are. One example we might see is the "end of vector - 1" pattern which comes e.g. from loop vectorization exit values. There may also be others. I don't yet really have a good sense here.

The fourth is generalized shuffle indices. (i.e. figuring out what lanes are demanded from a runtime shuffle mask) We're several steps from being able to talk about this concretely, and I'm not yet convinced we'll need anything here at all. If we do need to go here, this adds a huge amount of complexity. I'm hoping we don't get here.

I'm pretty sure we'll need to generalize at least as far as subvector insert/extract. I'm not sure about going beyond that yet.

Rematerialization of BuildVector idioms
=======================================

In SPEC runs, I'm seeing cases where we materialize a vector (most commonly a zero vector splat) and then spill that to the stack due to register pressure.  We should be able to rematerialize this during register allocation instead.

Note that there's two catches here:

1) the pass through operand on the instructions for vmv.v.i and vmv.s.x.  These prevent the operations from being trivially rematerializable.
2) we've inserted uses of VL and VTYPE in InsertVSETVLI before register allocation which are hard to trace through.

For the former, I see three options:

* Detect a implicit_def operand.  I tried this and couldn't get it working as the implicit_def has probably already been allocated, and we're no longer in SSA so.
* Version the intrinsics so we have one without a pass through operand.  Requires care during MI to MC lowering, and is bit ugly, but could probably be done.
* Add TAIL_UNDEF/MERGE_UNDEF flags.  Would be generically useful.

For the later, we may have to move VSETVLI post reg-alloc, or support a non-trivial form of remat (when the constant values in registers match).

Currently, the cases I'm seeing are mostly VL=2 and I think we can skin that cat differently, so this is more of a future item at the moment.

MachineLICM of Vector Constant Idioms
=====================================

If we have a constant pool load in the loop, we should be able to hoist it out.  Note that splats aren't interesting here as they're usually folded into the consuming instruction.

We should be able to *sink* into a loop to reduce register pressure.  This is a big deal at high LMUL.

Note that this may inter-related with the remat item above - if so, the focus might be different due to constant pool loads vs expanded build vector idioms.

TAIL_UNDEF
==========

We have multiple cases where we can better optimize a vector idiom knowing that the merge operand is undef.  See existing cases in RISCVInsertVSETVLI.cpp and above on rematerialization.


VL Widening/Narrowing
=====================

In VSETVLIInsert, we may be able to widen the VL for any instruction for which exeuction is guaranteed not to fault or have (observable) side effects.

If we had a robust form of that, we can consider VL narrowing optimizations earlier in the pipeline - specifically, SDAG.  This could allow rescalarization in some cases.

This could be used to support illegal vector types (i.e. <3 x i64>) efficiently (i.e. at VL=3), and maybe help with tail folding (via masking in IR).


Vector Remat and Spills for Short Vectors
=========================================

.. code::

   ; NOTE: Assertions have been autogenerated by utils/update_llc_test_checks.py UTC_ARGS: --version 2
   ; RUN: llc -mtriple=riscv64 -mattr=+v < %s | FileCheck %s

   define <2 x float> @test(<2 x float> %v) {
   ; CHECK-LABEL: test:
   ; CHECK:       # %bb.0:
   ; CHECK-NEXT:    addi sp, sp, -48
   ; CHECK-NEXT:    .cfi_def_cfa_offset 48
   ; CHECK-NEXT:    sd ra, 40(sp) # 8-byte Folded Spill
   ; CHECK-NEXT:    .cfi_offset ra, -8
   ; CHECK-NEXT:    csrr a0, vlenb
   ; CHECK-NEXT:    slli a0, a0, 1
   ; CHECK-NEXT:    sub sp, sp, a0
   ; CHECK-NEXT:    .cfi_escape 0x0f, 0x0d, 0x72, 0x00, 0x11, 0x30, 0x22, 0x11, 0x02, 0x92, 0xa2, 0x38, 0x00, 0x1e, 0x22 # sp + 48 + 2 * vlenb
   ; CHECK-NEXT:    addi a0, sp, 32
   ; CHECK-NEXT:    vs1r.v v8, (a0) # Unknown-size Folded Spill
   ; CHECK-NEXT:    vsetivli zero, 0, e32, mf2, ta, ma
   ; CHECK-NEXT:    vfmv.f.s fa0, v8
   ; CHECK-NEXT:    call expf@plt
   ; CHECK-NEXT:    vsetivli zero, 2, e32, mf2, ta, ma
   ; CHECK-NEXT:    vfslide1down.vf v8, v8, fa0
   ; CHECK-NEXT:    csrr a0, vlenb
   ; CHECK-NEXT:    add a0, sp, a0
   ; CHECK-NEXT:    addi a0, a0, 32
   ; CHECK-NEXT:    vs1r.v v8, (a0) # Unknown-size Folded Spill
   ; CHECK-NEXT:    addi a0, sp, 32
   ; CHECK-NEXT:    vl1r.v v8, (a0) # Unknown-size Folded Reload
   ; CHECK-NEXT:    vslidedown.vi v8, v8, 1
   ; CHECK-NEXT:    vfmv.f.s fa0, v8
   ; CHECK-NEXT:    call expf@plt
   ; CHECK-NEXT:    vsetivli zero, 2, e32, mf2, ta, ma
   ; CHECK-NEXT:    csrr a0, vlenb
   ; CHECK-NEXT:    add a0, sp, a0
   ; CHECK-NEXT:    addi a0, a0, 32
   ; CHECK-NEXT:    vl1r.v v8, (a0) # Unknown-size Folded Reload
   ; CHECK-NEXT:    vfslide1down.vf v8, v8, fa0
   ; CHECK-NEXT:    csrr a0, vlenb
   ; CHECK-NEXT:    slli a0, a0, 1
   ; CHECK-NEXT:    add sp, sp, a0
   ; CHECK-NEXT:    ld ra, 40(sp) # 8-byte Folded Reload
   ; CHECK-NEXT:    addi sp, sp, 48
   ; CHECK-NEXT:    ret
     %res = call fast <2 x float> @llvm.exp.v2f32(<2 x float> %v)
     ret <2 x float> %res
   }


   declare <2 x float> @llvm.exp.v2f32(<2 x float>)


In cases where we have vector values live over calls, we currently end up with some really awful spill fill sequences.

There's a couple of different ways of looking at this; fixing some subset of these is probably called for.

* The calling convention for exp doesn't have any callee saved vector registers.
* We could reschedule the vector extracts and inserts to reduce the need for vector registers over the calls.  This could be done as either some kind of scheduling/remat, or simply as a change to how we scalarize vector intrinsic calls.  (Or both.)
* We're spilling the scalable vector type, when we know that the minimum VLEN contains our value type.  Maybe we should add a special register class for fixed length values of this kind?  Or a family of such?  This may imply changes to the general legalize as scalable vector approach.

Note that this specific example *is not interesting*.  It's more a source of potentially interesting observations.

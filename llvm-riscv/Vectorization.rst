-------------------------------------------------
Open Items in Vectorization for RISCV
-------------------------------------------------

.. contents::

Loop Vectorizer
----------------

Loop Vectorization is fully implemented for both fixed and scalable vectors.  It has been fully enabled in upstream LLVM for several months, and is mostly on par with other targets.  The items mentioned below are mostly target specific enhancements - i.e. oppurtunities that aren't remquired for breakeven functionality.

In terms of performaning tuning, we're still in the early days.  I've been fixing issues as I find them.  Concrete bug reports for vector code quality are very welcome.

Tail Folding
++++++++++++

For code size reasons, it is desirable to be able to fold the remainder loop into the main loop body.  At the moment, we have two options for tail folding: mask predication and VL predication.  I've been starting to look at the tradeoffs here, but this section is still highly preliminary and subject to change.

Mask predication appears to work today.  We'd need to enable the flag, but at least some loops would start folding immediately.  There are some major profitability questions around doing so, particularly for short running loops which today would bypass the vector body entirely.

Talking with various hardware players, there appears to be a somewhat significant cost to using mask predication over VL predication.  For several teams I've talked to, SETVLI runs in the scalar domain whereas mask generation via vector compares run in the vector domain.  Particular for small loops which might be vector bottlenecked, this means VL predication is preferrable.

For VL predication, we have two major options.  We can either pattern match mask predication into VL predication in the backend, or we can upstream the work BSC has done on vectorizing using the VP intrinsics.  I'm unclear on which approach is likely to work out best long term.

Work on tail folding is currently being deferred until main loop vectorization is mature.

Epilogue Tail Folding
=====================

At the moment, my guess is that we're going to end up wanting *not* to tail fold the main loop (due to vsetvli resource limit concerns), and instead want to have a tail folded epilogue loop to run the tail in a single iteration.  At the moment, there is no support in the vectorizer for tail folded epilogues and a significant amount of rework will be needed.

One interesting point is that if we're (only) tail folding the epilogue loop, the relative importance of the predicate code quality drops significantly.  This may influence the masking vs VL predication decision from a pure engineering investiment perspective.

We may end up with a different strategy for loops which are known short.  There, the concern about vsetvli being a bottleneck is a lot less of a concern.  Maybe we'll tail fold the main loop in that case.

Tail Folding Gaps (via Masking)
===============================

Tail folding appears to have a number of limitations which can be removed.

* Some cases with predicate-dont-vectorize are vectorizing without predication.  Bug.
* Any use outside of loop appears to kills predication.  Oddly, on examples I've tried, simply removing the bailout seems to generate correct code?
* Stores appear to be tripping scalarization cost not masking cost which inhibits profitability.
* Uniform Store.  Basic issue is we need to implement last active lane extraction.  Note active bits are a prefix and thus popcnt can be used to find index.  No current plans to support general predication.

Tail Folding via Speculation
============================

This is mostly just noting an idea.  It occurs to me that if instructions in the loop are speculateable, we can "tail fold" via speculation.  That is, we can simply run the loop over the extra iterations, and then discard the result of any spurious elements.

.. code::

   // a is aligned by 16
   for (int i = 0; i < N; i++)
      sum += a[i];

.. code::

  // a is aligned by 16
  for (int i = 0; i < N+3; i += 4) {
      vtmp = a[i:i+3] // speculative load
      vtmp = select (splat(i) + step_vector < splat(N)), vtmp, 0
      vsum += vtmp
  }
  sum = reduce(vsum)


The above example relies on alignment implying access beyond a can't fault.  Note that this concept is *not* otherwise in LLVM's dereferenceable model, and is itself a fairly deep change.

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

   
Vectorization
=============


* Issues around epilogue vectorization w/VF > 16 (for fixed length vectors, i8 for VLEN >= 128, i16 for VLEN >= 256, etc..)
* Initial target assumes scalar epilogue loop, return to folding/epilogue vectorization in future.


Scalable Vectorizer Gaps
========================

Here is a punch list of known missing cases around scalable vectorization in the LoopVectorizer.  These are mostly target independent.

* Interleaving Groups.  This one looks tricky as selects in IR require constants and the required shuffles for scalable can't currently be expressed as constants.  This is likely going to need an IR change; details as yet unsettled.  Current thinking has shifted towards just adding three more intrinsics and deferring shuffle definition change to some future point.  Pending sync with ARM SVE folks.
* General loop scalarization.  For scalable vectors, we _can_ scalarize, but not via unrolling.  Instead, we must generate a loop.  This can be done in the vectorizer itself (since its a generic IR transform pass), but is not possible in SelectionDAG (which is not allowed to modify the CFG).  Interacts both with div/rem and intrinsic costing.  Initial patch for non-predicated scalarization up as `D131118 <https://reviews.llvm.org/D131118>`_
* Unsupported reduction operators.  For reduction operations without instructions, we can handle via the simple scalar reduction loop.  This allows e.g. a product reduction to be done via widening strategy, then outside the loop reduced into the final result.  Only useful for outloop reduction.  (i.e. both options should be considered by the cost model)


SLP Vectorization
-----------------

As of 7f26c27e03f1b6b12a3450627934ee26256649cd (June 14, 2023) SLP vectorization is enabled by default for the RISCV target.

The overall code quality still has a lot of room for improvement.  All of the known major issues have been at least partially handled, but we've likely got quite a bit of interative performance work ahead.  In general, codegen tends to be most sensative for short vectors (VL<4 or so).  This is where the benefit of vectorization is small enough that minor deficiencies in vector codegen (or SLP costing) lead to unprofitable results.



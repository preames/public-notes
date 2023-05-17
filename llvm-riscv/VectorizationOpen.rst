-------------------------------------------------
Open Items in Vectorization
-------------------------------------------------

.. contents::

Loop Vectorizer
----------------

Tail Folding
++++++++++++

For code size reasons, it is desirable to be able to fold the remainder loop into the main loop body.  At the moment, we have two options for tail folding: mask predication and VL predication.  I've been starting to look at the tradeoffs here, but this section is still highly preliminary and subject to change.

Mask predication appears to work today.  We'd need to enable the flag, but at least some loops would start folding immediately.  There are some major profitability questions around doing so, particularly for short running loops which today would bypass the vector body entirely.

Talking with various hardware players, there appears to be a somewhat significant cost to using mask predication over VL predication.  For several teams I've talked to, SETVLI runs in the scalar domain whereas mask generation via vector compares run in the vector domain.  Particular for small loops which might be vector bottlenecked, this means VL predication is preferrable.

For VL predication, we have two major options.  We can either pattern match mask predication into VL predication in the backend, or we can upstream the work BSC has done on vectorizing using the VP intrinsics.  I'm unclear on which approach is likely to work out best long term.

Work on tail folding is currently being deferred until main loop vectorization is mature.

Tail Folding Gaps (via Masking)
===============================

Tail folding appears to have a number of limitations which can be removed.

* Some cases with predicate-dont-vectorize are vectorizing without predication.  Bug.
* Any use outside of loop appears to kills predication.  Oddly, on examples I've tried, simply removing the bailout seems to generate correct code?
* Stores appear to be tripping scalarization cost not masking cost which inhibits profitability.
* Uniform Store.  Basic issue is we need to implement last active lane extraction.  Note active bits are a prefix and thus popcnt can be used to find index.  No current plans to support general predication.



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

I've run reasonable broad functional testing without issue.  However, SLP is still disabled by default due to code quality problems which have not yet been adddressed.

The major issues for SLP/RISCV I currently know of are:

* We have a cost modeling problem for vector constants. SLP mostly ignores the cost of materializing constants, and on most targets that works out mostly okay. RISCV has unusually expensive constant materialization for large constants, so we end up with common patterns (e.g. initializing adjacent unsigned fields with constants) being unprofitably vectorized. Work on this started under D126885, and there is ongoing discussion on follow ups there.
* We will vectorize sub-word parallel operations and don't have robust lowering support to re-scalarize. Consider a pair of i32 stores which could be vectorized as <2 x i32> or could be done as a single i64 store. The later is likely more profitable, but not what we currently generate. I have not fully dug into why yet.

Note that both of these issues could exist for LV in theory, but are significantly less likely. LV is strongly biased towards constant splats and longer vectors. Splats are significantly cheaper to lower (as a class), and longer vectors allows fixed cost errors to be amortized across more elements.

Another concern is that SLP doesn't always respect target register width and assumes legalization.  I somewhat worry about how this will interact with LMUL8 and register allocation, but I think I've convinced myself that the same basic problem exists on all architectures.  (For reference, SLP will happily generate a 128 element wide reduction with 64 bit elements.  On a 128 bit vector machine, that requires stack spills during legalization.)  Such sequences don't seem to happen in practice, except maybe in machine generated code or cases where we've over-unrolled.  


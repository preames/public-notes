-----------------------------------
Vectorization - Ideas and Reference
-----------------------------------

This page is intended as a reference on various vectorization related topics I find myself needing to explain/describe/reference on a somewhat regular basis.

.. contents::


Trip Count Required for Profitability
-------------------------------------

For a given loop on a given piece of hardware, there is some minimum number of iterations required before a given vector loop is profitable over the equivalent scalar loop.  This is highly dependent both on micro architecture and vectorization strategy.

On most hardware, the tradeoff point will be in the high single digits to low double digits of executions.  It is common to have tradeoff points for floating point loops be lower than integer loops.  This happens because modern OOO processors frequently have more integer than FP resources, and may even share the vector and FP resources.

It may also be the case that vectorization is profitable for some trip count TC, but not for TC + 1.  This happens due to the need to handle tail iterations, and the overheads involved.  *Usually* if TC + 1 is not profitable, it's at least "close to" the scalar loop in performance, but exceptions do exist.


Tail Handling
-------------

Given a loop with a trip count (TC), and a desirable vectorization factor (VF), it is unlikely that TC % VF == 0.  You could artificially limit vectorization to cases where this property holds, but in practice that disallows all loops with runtime trip counts, so we don't.  The remainder iterations are often called the "tail iterations".

We have a couple major options here:

* Use a scalar loop to handle the remainder elements
* Use a predicated straight line sequence
* Fold the predication into the main loop body.
* Use a loop with a smaller vector factor, possibly combined with the previous choices.

The assumption for the remainder of this section is that we run TC - TC % VF iterations of the original loop in our newly inserted vector loop, and are figuring out how to execute the remaining TC % VF iterations.

Note that the problem we're talking about here is a particular form of iteration set splitting, combined with some profitability heuristics.  Remembering this point is helpful when reasoning about correctness.

**Scalar Epilogue**

The simplest technique is to simply keep the scalar loop, and branch to it with incoming induction variable values which reflect the iterations completed in the vector body.  

This technique is advantegous when the scalar loop is required for other reasons (i.e. runtime aliasing check fallback), or the number of remaining iterations is expected to be short.  As such, it tends to be most useful when the chosen VL is relatively small.

Note that all the usual loop optimization choices apply, but with the additional known fact that the new loops trip count is < VF.  This (for instance) may result in extremely different loop unrolling profitability.

**Predicated (Non-Loop) Epilogue**

You can generate a single peeled vector iteration with predication.  This can be done with either software or hardware techniques (see below), but is usually only profitable with hardware support.

This technique works well when the remainder is expected to be large relative to the original VF.

**Tail Folded (Predicated) Main Loop**

As with the previous item, but with the extra iteration folded into the main vector body.  This involves computing a predicate on every iteration of the main loop, and predicating any required instructions.

On most hardware I'm aware of, a tail folded loop will run slower than the plain vector loop without predication.  So for very long trip counts, this can be non-optimal.  The tradeoff is (usually) a massive reduction in code size.

This choice can also hurt for short running loops.  If TC is significantly lower than VF, then a scalar loop might be significantly better.

Note that in the case I'm describing here, all but the last iteration of the vector loop run the same number of iterations of the original loop.  There's a related idea (called EVL vectorization in LLVM) where this property changes.  

**Epilogue Vectorization**

After performing the iteration set splitting for the original loop using our chosen vector factor, we can choose some other small vectorization factor - call it VF2 - and vectorize the remainder loop.  In principle, you can keep doing this recursively, but in practice, we tend to stop after the second.  Since the second vector.body may still have tail iterations, you need to pick one of the other techniques here as a fallback.

The benefit of this technique is that you have *multiple* vector bodies, each with independent VF, and can dispatch between them at runtime.  

The only case LLVM uses this technique is when VF is large compared to expected TC.  Specifically, some cases on AVX512 fallback to AVX2 loops.


Forms of Predication
--------------------

Predication is a general technique for "masking off" (that is, disabling) individual lanes or *otherwise avoiding faults in inactive lanes*.  Note that depending on usage, the result of the operations on the inactive lanes may either be defined (usually preserved, but not always) or undefined.

I tend to only be interested in the case where the result is undefined as that's the one which arrises naturally in compilers.  Our goal is basically to avoid faults on inactive lanes, and nothing else.

There are both hardware and software predication techniques!

The most common form of hardware predication is "mask predication" where you have a per-lane mask which indicates whether a particular lane is active or not.

RISCV also supports "VL predication", "VSTART predication", and "LMUL predication".  (These are my terms, not standardized.)  Each of them provides a way to deactivate some individual set of lanes.   Out of them, only VL predication is likely to be performant in any way, please don't use the others. 

In software, the usual tactic is called "masking" or "masking off".  The basic idea is that you conditionally select a known safe (but otherwise useless) value for the inactive lanes.  For a divide, this might look like "udiv X, (select mask, Y, 1)".  For a load, this might be "LD (select mask, P, SomeDereferenceableGlobal)".  There is no masking technique for stores.

There's also an entire family of related techniques for proving speculation safety (i.e. the absence of faults on inactive lanes *without* masking).  This isn't predication per se, but comes up in all the same cases, and is (almost) always profitable over any form of predication.

.. header:: This is a collection of examples and ideas for potential loop opts in LLVM.  This is mostly a dumping ground for things I've written up once and want to be able to reuse later.

-------------------------------------------------
LLVM Loop Opt Ideas
-------------------------------------------------

.. contents::

Multiple Exit Loops
-------------------

See my talk on the subject from the LLVM Developers Conference in 2020.  

See also `my proposal <https://lists.llvm.org/pipermail/llvm-dev/2019-September/134998.html>`_ to llvm-dev from back in 2019 on extending the loop vectorizer to support multiple exit loops.  I have some patches which support the most basic cases.  The last one was reverted due to an exposed bug, and I haven't had time to isolate it just yet.

Note that when I talk about multiple exits, I am generally only talking about the case where each exit dominates the latch block of the loop.  The case where an exit is conditional and doesn't dominate the latch is much rarer and harder to easily handle.

Cornercases
===========

Here's a brief overview of the cornercases which come up when extending an optimization from bottom tested loops to multiple exit loops:

* Multiple distinct exit blocks.  This includes the mechanics of iterating either exiting blocks or exit blocks to ensure each exiting edge is covered.  Mostly, this is just updating existing code to do things like updating LCSSA for each exit block.
* Multiple exiting blocks which share an exit block, but without LCSSA PHI nodes.  This requires getting the CFG right, but doesn't need to handle general LCSSA construction just yet.
* Multiple exiting blocks which share an exit block with LCSSA PHI nodes. This cornercase generally requires reframing some of the per-exit logic in terms of per exiting edge logic.  There's often some subleties in there.

I generally try to tackle the first two before the third.  Adding the appropriate bailout tends to be simple, and it lets me build a test corpus incrementally. 

Runtime Unrolling
+++++++++++++++++

`D107381 <https://reviews.llvm.org/D107381>`_ takes the first steps towards supporting a more general form of multiple exit loops.  The following is a collection of notes/tasks I thought of when drafting it.

* Prolog support.  The above only handle epilogue case.  Not sure how much work if any needed here, mostly audit and test.
* Should we prefer epilogue?  By using "required scalar epilogue" trick, we can eliminate *all* analyzeable exits from the main loop.  We can't do this in the prolog case.
* Cost modeling is unclear, but maybe we should discount exits eliminateable with the above "required scalar epilogue" trick?
* Interestingly, the code in runtime unrolling implements a generic iteration set splitting transform combined with heuristics to pick the split point.  Probably worth pulling that out for reuse and (frankly) simplify testing.  Time to write a simple iteration set splitting pass?  

Uniform Lanes
-------------

When unrolling (or vectorizing), it's not uncommon to encounter expressions which are uniform (unchanging) across 2 or more contigous iterations of the loop.  This computation does not need to be repeated, and can thus discount costing in the unroll cost model to allow us to unroll larger loops than would otherwise be profitable.

Canonical examples:

.. code::

   for (int i = 0; i < N; i++) {
     // uniform across 8 iterations at a time
     a = i / 8;
     
     // If unrolled by 8, consists of a fixed base (per unrolled iteration) 
     // plus a loop invariant term
     b = i % 8.
     
     // xor recurrences repeat between two values (and thus alternating lanes are uniform)
     // (Beyond unrolling, peeling by two also is profitable for this case since
     //  the terms of the recurrence become entirely invariant in the loop.)
     c = c ^ 0xFF
   }

I'd started work in this (https://reviews.llvm.org/D91481, https://reviews.llvm.org/D91451), but am largely no longer work on this if anyone wants to pick it up.  

Internal Control Flow 
---------------------
(Specifically, the subset where where Iteration Set Splitting is possible.)

A couple of general comments.

I really don't think that extending IRCE is the right path forward here. IRCE has some serious design defects, and I'm honestly quite nervous about it's correctness. I think that iteration set splitting (the basic transform IRCE uses) is absolutely something we should implement for the main pipeline, but I'd approach it as building new infrastructure to replace IRCE, not as getting IRCE on by default. In particular, I suspect the value comes primarily from a cost model driven approach to splitting, not IRCE's unconditional one.

Second, I advise being very cautious about going directly for the general case here. The general case for this is *really really hard*. If it wasn't, we'd already have robust solutions. If you can describe your motivating examples in a bit more depth (maybe offline), we can see if we can find a specific sub-case which is both tractable and profitable.

Example under discussion:

.. code::

   loop.ph:
     br label %loop

   loop:
     %iv = phi i64 [ %inc, %for.inc ], [ 1, %loop.ph ]
     %cmp = icmp slt i64 %iv, %a
     br i1 %cmp, label %if.then.2, label %for.inc

   if.then.2:
     %src.arrayidx = getelementptr inbounds i64, i64* %src, i64 %iv 
     %val = load i64, i64* %src.arrayidx
     %dst.arrayidx = getelementptr inbounds i64, i64* %dst, i64 %iv 
     store i64 %val, i64* %dst.arrayidx
     br label %for.inc

   for.inc:
     %inc = add nuw nsw i64 %iv, 1
     %cond = icmp eq i64 %inc, %n
     br i1 %cond, label %exit, label %loop

   exit:
     ret void


In this example, forming the full pre/main/post loop structure of IRCE is overkill.  Instead, we could simply restrict the loop bounds in the following manner:

.. code::

   loop.ph:
     ;; Warning: psuedo code, might have edge conditions wrong
     %c = icmp sgt %iv, %n
     %min = umax(%n, %a)
     br i1 %c, label %exit, label %loop.ph

   loop.ph.split:
     br label %loop

   loop:
     %iv = phi i64 [ %inc, %loop ], [ 1, %loop.ph ]
     %src.arrayidx = getelementptr inbounds i64, i64* %src, i64 %iv 
     %val = load i64, i64* %src.arrayidx
     %dst.arrayidx = getelementptr inbounds i64, i64* %dst, i64 %iv 
     store i64 %val, i64* %dst.arrayidx
     %inc = add nuw nsw i64 %iv, 1
     %cond = icmp eq i64 %inc, %min
     br i1 %cond, label %exit, label %loop

   exit:
     ret void

I'm not quite sure what to call this transform, but it's not IRCE.  If this example is actually general enough to cover your use cases, it's going to be a lot easier to judge profitability on than the general form of iteration set splitting.  

Another way to frame this special case might be to recognize the conditional block can be inverted into an early exit.  (Reasoning: %iv is strictly increasing, condition is monotonic, path if not taken has no observable effect)  Consider:

.. code::

   loop.ph:
     br label %loop

   loop:
     %iv = phi i64 [ %inc, %for.inc ], [ 1, %loop.ph ]
     %cmp = icmp sge i64 %iv, %a
     br i1 %cmp, label %exit, label %for.inc

   for.inc:
     %src.arrayidx = getelementptr inbounds i64, i64* %src, i64 %iv 
     %val = load i64, i64* %src.arrayidx
     %dst.arrayidx = getelementptr inbounds i64, i64* %dst, i64 %iv 
     store i64 %val, i64* %dst.arrayidx
     %inc = add nuw nsw i64 %iv, 1
     %cond = icmp eq i64 %inc, %n
     br i1 %cond, label %exit, label %loop

   exit:
     ret void
   

Once that's done, the multiple exit vectorization work should vectorize this loop. Thinking about it, I really like this variant.  


Should SCEV be an optimizeable IR?
----------------------------------

Background
++++++++++

SCEV canonicalizes at construction.  That is, if two SCEV's compute equivalent results, the goal is to have them evaluate to the same SCEV object.  Given two SCEVs, it's is safe to say that if S1 == S2 that the expressions are equal.  Note that it is not safe to infer the expressions are different if S1 != S2 as canonicalization is best effort, not guaranteed.

SCEV's handling of no-wrap flags (no-self-wrap, no-signed-wrap, and no-unsigned-wrap) is complicated.  The key relevant detail is that wrap flags are sometimes computed *after* SCEV for the underlying expressions have been generated.  As such, there can be cases where SCEV (or a user of the SCEV analysis) learns a fact about the SCEV which could have led to a more canonical result if known at construction.  The basic question is what to do about that.

Today, there are three major options - with each used somewhere in the code.

* Move inference to construction time.  This has historical been the best option, but recent issues with compile time is really calling this into question.  In particular, it's hard to justify when we don't know whether the resulting fact will ever be useful for the caller.
* Update the SCEV node in place, and then "forget" all dependent SCEVs.  This requires collaboriation with SCEV's user, and can only be done externally.  It also requires all dependent SCEV's to rebuild from scratch which has been a compile time issue in recent patches.
* Update the SCEV node in place, and then leave dependent SCEVs in an inprecise state.  (That is, if we recreated the same expression, we'd end up with a more canonicalized result.)  This results in potentially missed optimizations, and implementation complexity to work around the inprecision in a few spots.

What if?
++++++++

So, what might we do here?

The basic idea is that we explicitly allow SCEVs to be non-canonical.  For the purpose of this discussion, let's focus on the flag use case.  There are potentially others for non-canonical SCEVs, but we'll ignore that for now.  Then, we support the ability to a) refine existing SCEVs, and b) revisit the instructions associated with dependent SCEVs and produce new more-canonical SCEVs.

Let me expand on that last bit because it's subtle in an important way.

SCEV internally maintains a map from `Value*` to `SCEV*` (i.e. the `ValueExprMap` structure).  Today, ever existing SCEV has a potentially many to one mapping from `Value*` to `SCEV*`.  We would extend that to a many-to-many relation with potentially _multiple_ SCEV nodes corresponding to each Value.  The first in that list would be the best currently known, and all others would be stale values (potentially used by some client until explicitly forgotten).

Given this, we'd then have the option to handle a new wrap flag with the following procedure:

.. code::

  Mutate the SCEV whose fact we inferred.
  for each Value* mapper to said SCEV {
    add users to worklist
  }
  while worklist not empty {
    if no existing SCEV for Value *V, ignore
    reconstruct SCEV for Value *V
      (note that at least one operand of the expression must have
      either changed or been mutated)
    if changed
      add to mapping
      add users of V to worklist
  }

The key detail here is that we're walking the user list of the Value, not of the SCEV.  The SCEV still doesn't have an explicit use list.  We're also not deleting old SCEV nodes.

If we want the invariant that getSCEV(V) always returns the most canonical form, then we need to apply the above algorithm eagerly on change.  If we're okay giving that up, then we can do this specifically on demand only, but that complicates the SCEV interface.  I'd start with the former until we're forced into the later.

Risks
+++++

SCEV* Keyed Maps
  If there are maps keyed by SCEV* in client code, and the client expects map[getSCEV(V)] to return an expected result, the change of invariant might break client code.  I am not currently aware of such a structure, but also haven't auditted for it.

Update time
  The need to walk use lists may be expensive.  The existing forget interface gives an idea, but we might be able to accelerate this using a "pending update" lazy mechanism.  Haven't fully explored that.

Current thinking
++++++++++++++++

After writing this up, I'm left with the impression this was a lot cleaner than I'd first expected.  I'd sat down to write this up as one of those crazy ideas for someday; I'm now wondering if someday should be now.

    








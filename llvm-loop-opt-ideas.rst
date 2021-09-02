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
=================

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
==========

SCEV canonicalizes at construction.  That is, if two SCEV's compute equivalent results, the goal is to have them evaluate to the same SCEV object.  Given two SCEVs, it's is safe to say that if S1 == S2 that the expressions are equal.  Note that it is not safe to infer the expressions are different if S1 != S2 as canonicalization is best effort, not guaranteed.

SCEV's handling of no-wrap flags (no-self-wrap, no-signed-wrap, and no-unsigned-wrap) is complicated.  The key relevant detail is that wrap flags are sometimes computed *after* SCEV for the underlying expressions have been generated.  As such, there can be cases where SCEV (or a user of the SCEV analysis) learns a fact about the SCEV which could have led to a more canonical result if known at construction.  The basic question is what to do about that.

Today, there are three major options - with each used somewhere in the code.

* Move inference to construction time.  This has historical been the best option, but recent issues with compile time is really calling this into question.  In particular, it's hard to justify when we don't know whether the resulting fact will ever be useful for the caller.
* Update the SCEV node in place, and then "forget" all dependent SCEVs.  This requires collaboriation with SCEV's user, and can only be done externally.  It also requires all dependent SCEV's to rebuild from scratch which has been a compile time issue in recent patches.
* Update the SCEV node in place, and then leave dependent SCEVs in an inprecise state.  (That is, if we recreated the same expression, we'd end up with a more canonicalized result.)  This results in potentially missed optimizations, and implementation complexity to work around the inprecision in a few spots.

What if?
========

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
=====

SCEV* Keyed Maps
  If there are maps keyed by SCEV* in client code, and the client expects map[getSCEV(V)] to return an expected result, the change of invariant might break client code.  I am not currently aware of such a structure, but also haven't auditted for it.

Update time
  The need to walk use lists may be expensive.  The existing forget interface gives an idea, but we might be able to accelerate this using a "pending update" lazy mechanism.  Haven't fully explored that.

Current thinking
================

After writing this up, I'm left with the impression this was a lot cleaner than I'd first expected.  I'd sat down to write this up as one of those crazy ideas for someday; I'm now wondering if someday should be now.

    
Unroll Heuristics
-----------------

In generic discussion of unrolling cost heuristics, I typically see two distinct families of reasoning.

**Heuristic 1 - Direct Simplification**

Unrolling a loop will sometimes enable elimination of computation.  For the purposes of this heuristic, latch cost is generally *not* relevant (that's covered in Heuristic 2).  The only catch is that even to simplify, we generally don't want to unroll enough to fall out of cache.

A couple examples which probably should be unrolled:

... code::

  for (i in 0 to N) { 
    a[i/2)++; 
  }

  for (i in 0 to N) { 
    if (cant_analyze())
      break;
    g_a = 5;
  }

  for (i in 0 to N) {
    if (f(i/2))
      break;
    a[i)++; 
  }

  for (i in 0 to N) {
    if (i % 2 == 0)
      a[i)++; 
  }


For each of these, we're balancing estimated dynamic cost vs static cost.  Note that the static cost doesn't necessarily increase.  On the first and last example, the static cost is unchanged.  

The case with a unchanged static cost is arguably a canonicalization heuristic and is justifiably on it's own, but it's hard to clearly split from the balanced cost case.

**Hueristic 2 - Branch Cost**

The other major reason to unroll is to reduce the branch cost of the loop structure itself.  Here, it's important to have a mental model of the hardware as different processors have *radically* different branch costs.  The primary factors being traded off are:

* Effective out of order width.  This is primarily a function of a) the number of branches, and b) their predictability.  Note that predictors can match non-trivial patterns which complicates reasoning about unrolling short loops substaintially.
* Prediction resources.  Every predictable branch requires predictor state which can't be used elsewhere, and may behave differently in hot and cold code.  
* Code size.  Primarily a question of whether hot code fits into the relevant cache structures (uop cache dominates, L1 is also worth considering).  Falling out of cache generally hurts badly.  There's both a per-loop local effect, and a program hot-code global effect.

... code::

  for (i in 0 to N) {
    a[i] = i;
  }

Consider the loop above for a couple different scenarios.  We'll start with partial or runtime unrolling, and then move to full unrolling.

* A simple in-order core or an out-of-order code without a good branch predictor.  Unrolling to smallest cache size likely beneficial due to reducing number of branches.
* Out of order with dedicated loop predictor.  Likely *not* worthwhile to unroll single exit loops.  For multiple exit loops, reasoning for non-latch exits is same as following case without loop predictor.
* Out of order w/o loop predictor.  For single exit loops, probably not worthwhile as we're still going to mispredict the last iteration (unless the unrolled trip count is small enough that we better fit the predictors pattern capability.)  For multiple exit loops, may be justified if total number of branches in the unrolled loop is equal or less than the original unrolled loop.

Full unrolling is generally profitable anywhere partial unrolling by the same factor is, but may additionally be profitable when:

* Out of order w/o loop predictor.  For *long* running loops, probably not worthwhile as branch mis-predict cost is ammortized away.  For short loops with *cosistent* trip counts, likely worthwhile to reduce mis-predict costs.  

In general, on modern high performance out-of-order processors, unrolling is generally *not* a good default.  On simpler cores, it often *is* a good default.

**Alternate Framings**

There are three alternate views of the heuristics above which are sometimes helpful.

First, the complexity of the branch cost heuristic is arguably just a (very) complicated cost model for the dynamic cost of the first heuristic.  You can integrate the two heuristics into one - at least for the local cost.

Second, the local cost vs global cost axis is important.  It is generally *very* hard for compiler to reason about the global effect of an increase in code size or predictor resource use.  I don't know of any good answers here other than to be slightly conservative in the unrolling heuristic.  You might be able to use profile data to predict preloops or post-loops untaken in runtime unrolling, and thus consider them to have zero global cost, but I haven't see anyone do that successfully yet.

Third, while we've discussed them in terms of unrolling, the same basic reasoning applies to a number of loop transforms such as peeling (first and last), and iteration set splitting.


SCEV Wrap Flags
---------------

This section is inspired by the discussion on `D106852 <https://reviews.llvm.org/D106852>`_.  This review starts with a problem around AddRecs.  This is my attempt at getting my head around the problem in advance of participating in the review discussion.

Aside: Please excuse the mix of psuedo code, this is my best attempt at making the examples readable.

First, the problem from the review
==================================

.. code::

  %c = add i32 %a, %b
  if (%c would not overflow) {
    loop {
      %iv = [%a, %preheader], [%iv.next, %loop]
      body;
      %iv.next = add i32 nuw %iv, %b
      if (function_of_unrelated_iv) break;
    }
    return;
  }
  code_which_assumes_overflow()

The basic structure of this example is a conditionally executed loop where %iv.next is known not to overflow on the first iteration based on control flow which gaurds the entry to the loop. 
    
Naively, SCEV should produce expressions which look roughly like the following:

* %c = %a + %b
* %iv = {%a, +, %b}<nuw>
* %iv.next = {%a +nuw %b, +, %b}

The problem is that SCEV doesn't include flags in object identity.  As a result, what SCEV actually produces is:

* %c = %a +nuw %b
* %iv = {%a, +, %b}<nuw>
* %iv.next = {%a +nuw %b, +, %b}

This happens because SCEV sees two add(%a,%b) functions and canonicalizes them to the same SCEV object.  (Warning: The example chosen for explaination is deliberately simplified and problably *does not* produce these broken SCEVs.  See the unreduced cases in `D106851 <https://reviews.llvm.org/D106851>`_ for something which demonstrates this in practice.)

This is the problem that the review mentioned at the beginning describes.  The review proposes to fix it by dropping the nuw flag on the computation of the starting value of the %iv.next AddRec, and thus having the resulting SCEVs become:

* %c = %a + %b
* %iv = {%a, +, %b}<nuw>
* %iv.next = {%a + %b, +, %b}

This would seem to be correct in this case, but we'd loose optimization potential from knowing that %a + %b doesn't overflow in the context of the starting value for the %iv.next AddRec.

Isn't this just CSE?
====================

Looking at the above, it seems like this problem is simply common sub-expression elimination.  Given that, let's explore how the CSE piece is handled.

.. code::

  define i1 @test(i32 %a, i32 %b, i1 %will_overflow) {
    %c = add i32 %a, %b
    br i1 %will_overflow, label %exit1, label %exit2

  exit1:
    %ret1 = icmp ult i32 %c, %a
    ret i1 %ret1

  exit2:
    %c2 = add nuw i32 %a, %b
    %ret2 = icmp ult i32 %c2, %a
    ret i1 %ret2
  }

  $ opt -enable-new-pm=0 -analyze -scalar-evolution flags.ll 
  Printing analysis 'Scalar Evolution Analysis' for function 'test':
  Classifying expressions for: @test
    %c = add i32 %a, %b
    -->  (%a + %b) U: full-set S: full-set
    %c2 = add nuw i32 %a, %b
    -->  (%a + %b) U: full-set S: full-set
  Determining loop execution counts for: @test

Interestingly, we still combined both adds into a single SCEV node, but we did so conservatively.  We stripped the flags from *both* expressions.  This is the classic solution uses for CSE elsewhere in the optimizer as well.

So, all is good right?  Well, not so fast.  The problem is the above wasn't implement as merging the flags on CSE.  Instead, it was implemented via `getNoWrapFlagsFromUB` and `isSCEVExprNeverPoison`.

`isSCEVExprNeverPoison` contains a bit of logic which is *extremely* subtle.  Specifically, it returns true for the following circumstance:

* an *instruction* whose operands include some AddRec in some loop L
* all other operands to the add are invariant in L
* the add is guaranteed to execute on entry to L
* we can prove that poison, if produced by the add, must reach an instruction which triggers full UB

The basic idea behind this appears to be that by a) finding the defining loop for the instruction, and b) proving the defining instruction executes, we prove the flags must be correct for all uses of the SCEV.  After staring at this for a while, I believe this correct.

Back to our original problem
============================

The key point of the digression through CSE is that the requirements for preserving the flags of an add dependent on three aspects: 1) the defining scope, 2) guaranteeing that an instruction must execute in that scope, and 3) establishing overflow must reach an instruction which triggers UB.

The problem the original review is trying to tackle comes down to our choice to preserve flags on the %a + %b expression in the start of the addrec for %iv.next.  However, it's missing both the guaranteed to execute property, and the poison triggers-UB property.  So, I'm not sure it's a complete fix.

There's also a separate concern which has been raised in the review about multiple operand add expressions, and the correctness of flag splitting, but I don't think we need to get to that to already have a problem.

An interesting case...
======================

.. code::

   define i1 @test2_a(i32 %a, i32 %b, i1 %will_overflow) {
   entry:
     br i1 %will_overflow, label %exit1, label %loop

   loop:
     %iv = phi i32 [%a, %entry], [%iv.next, %loop]
     ;; SCEV produces {(%a + %b)<nuw><nsw>,+,%b}<nuw><nsw><%loop>
     %iv.next = add nuw nsw i32 %iv, %b
     %trap = udiv i32 %a, %iv.next ;; Use to force poison -> UB
     %ret2 = icmp ult i32 %iv.next, %a
     ; Note: backedge is unreachable here
     br i1 %ret2, label %loop, label %exit2

   exit2:
     ret i1 false

   exit1:
     ;; SCEV produces (%a + %b)<nuw><nsw>
     %c = add i32 %a, %b
     %ret1 = icmp ult i32 %c, %a
     ret i1 false
   }

   define i1 @test2_b(i32 %a, i32 %b, i1 %will_overflow) {
   entry:
   br i1 %will_overflow, label %exit1, label %loop

   exit1:
     ;; SCEV produces (%a + %b)
     %c = add i32 %a, %b
     %ret1 = icmp ult i32 %c, %a
     ret i1 false

   loop:
     %iv = phi i32 [%a, %entry], [%iv.next, %loop]
     ;; SCEV produces {(%a + %b)<nuw><nsw>,+,%b}<nuw><nsw><%loop>
     %iv.next = add nuw nsw i32 %iv, %b
     %trap = udiv i32 %a, %iv.next
     %ret2 = icmp ult i32 %iv.next, %a
   ; Note: backedge is unreachable here
   br i1 %ret2, label %loop, label %exit2

   exit2:
     ret i1 false
   }

The first example, as expected, produces an incorrect SCEV expression for %c.  The second example, which is simply the first with blocks in different order, produces something I don't understand at all.  We seem to have gotten two *different* add scevs here.  That doesn't fit my understanding of the code at all.

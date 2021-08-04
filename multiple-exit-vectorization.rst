-------------------------------------------------
Multiple Exit Loop Vectorization in LLVM
-------------------------------------------------

I recently spent some time working on support for vectorization of loops with multiple exits in LLVM's loop vectorizer.  This writeup is intended to showcase some of the work, and highlight areas for future investment.

.. contents::

Background
------------

At it's heart, the loop vectorizer was built to handle cases like the following:

.. code::

   int i = 0;
   if (i < N) {
     do {
      a[i] = i;
      i++;
    } while (i < N);
  }

This is lowered into a form of a for(int i = 0; i < N; i++) loop.  There are a couple of key things to notice:

* It has a bottom tested exit condition.  This means that only the latch block exits the loop.
* It has a loop guard before the loop which ensures the exit condition is true on initial entry to the loop.
* Because the sole exit is also the loop latch (the source of the backedge), all instructions within the loop execute an equal number of times.

In addition, the loop vectorizer has support for internal predication.  That is, the body of the loop can contain instructions which execute conditionally.

Supporting Non-Latch Exits
--------------------------

The core challenge to vectorizing a multiple exit loop is that various instructions within the loop need to execute a different number of times.  Consider the example:

.. code::

   for (int i = 0; i < 2; i++) {
     a[i] = 0;
     if (i > 0)
       break;
    b[i] = 0;
  }
   
In this example, the first two elements of 'a' are written to, but only the first element of 'b' is written to.

Worth noting is that this problem is not unique to *multiple* exit loops.  Any single exit loop which exits from any block other than the latch also has the same problem.

To increase confidence in the implementation strategy, I implemented support for single non-latch exits before unblocking multiple exits.  This turned out to be a very good thing, as we found and fixed a couple nasty bugs at this stage before moving on to multiple exit loops.

The vectorizer already had support for using a scalar epilogue loop - useful when you want to vectorize, but don't know whether the trip count is evenly divisible by your vectorization factor.  I was able to repurpose that infrastructure to solve the non-latch exit problem.

Given a loop of the form:

.. code::

   i = 0;
   loop {
     a[i] = 0;
     if (i > N)
       break;
     b[i] = 0;
     i++;
   }

We can vectorize this with a vector factor of 4 by doing the following:

.. code::

   i = 0;
   if (N > 4) {
     NVec = N % 4 == 0 ? N - 4 : N - N % 4;
     do {
       a[i:i+3] = 0;
       b[i:i+3] = 0;
       i+=4;
     } while (i != NVec);
   }
   loop {
     a[i] = 0;
     if (i > N)
       break;
     b[i] = 0;
     i++;
   }

In this example, we've created a four wide vector loop that runs sets of four iterations without checking for the exit condition in between the two stores by ensuring that the *last* iteration of the original scalar loop must *always* run in the scalar epilogue loop which follows.

The key changes neeed to support this were:

* Auditting the vectorizer source and fixing a number of places where the exit was assumed to also be the latch for historical reasons.
* Extending the existing 'requireScalarEpilogue' mechanism to *unconditionally* branch to the epilogue loop.
* Adding "has a non-latch exit" as a reason to require a scalar epilogue.

Worth noting is that this transform only works when we can compute a precise trip count for the original scalar loop.  Thankfully, SCEV has a bunch of infrastructure for that already and the vectorize gets to imply rely on it.  It is worth noting that SCEV is only able to analyze loop exits which dominate the latch.  As a result, the vectorizer is also limited to vectorizing loops where all exits dominate the latch.

The Mechanics of Multiple Exits
-------------------------------

As described over in my generic `multiple exit loop notes <https://github.com/preames/public-notes/blob/master/llvm-loop-opt-ideas.rst#cornercases>`_, there's generalization needed to support multiple exits and in particular, exit blocks shared by multiple exiting blocks.

In this particular case, I did some prework in af7ef895d, handled everything except shared exit blocks with LCSSA phis in e4df6a40dad, and finished the generalization in 9f61fbd.


Open Topics
-----------

This section would be titled "future work", but at the moment, I'm not planning to continue working in this area.  I acheived my primary objective, and don't have any incentive to push this further.

Currently, only loops with entirely statically analyzeable exits are supported.  Analyzeable specifically means that SCEV's `getExitCount(L, ExitingBB)` returns a computable result.

Conditionally taken exiting blocks
==================================

To support conditionally reached exit tests, we'll need to generalize SCEV's exit count logic.  This is unfortunately, a very subtle set of changes as it requires shifting how we reason about poison and overflow.  (In short, we can't assume an IV becoming poison implies the backedge isn't taken on that iteration.)

Example:

.. code::

   loop {
     if (cond())
       bar();
       if (cond2())
         break;
   }

It's worth noting that without the call to `bar()` in the above, SimplifyCFG will happily convert that loop exit into `if (cond() && cond2())` which is enough to let us analyze the upper bound of the exit assuming only `cond2()` is analyzeable, and the exact trip count if both conditionals are.  It's not clear how common examples with `bar()` actually are.

Data dependent exits
====================

If we have exits which dominate the latch, but are not analyzeable, we can sometimes form predicates which allow us to vectorize (e.g. widen operations) anyways.  Example:

.. code::

   // Classic b[a[i]] reduction with a range check on 'b'.
   loop {
     x = a[i];
     if (x < N) break;
     sum += b[x];
   }

To highlight why this is hard, imagine that `a` is exactly one element long, and the range check fails on that first iteration.  Now align our one element `a` array such that `a[1]` would live on another page which would fault on access.
     
Let's enumerate some cases we could handle without solving the "general" problem.  All of these share a common flavor; we need to identify a precise runtime bound for a non-faulting access.  Once we have that, we can either:

* Clamp the iteration space of the vectorized loop to the umin of the otherwise computable trip count and our safe region.  In this case, our vectorize loops run only up to 'a
* Generate a predicate mask for each load which is independent of the loop CFG and depends solely on the static size information.

Either way, we can ensure that either `a[1]` doesn't execute, or that if it does, hardware predication masks the fault.

Statically Known Array Sizes
  If both `a` and `b` are statically sized (e.g. allocas, globals, etc..), we can form trivial bounds.

Dynamically Known Array Sizes
  We can generalize the former for any allocation whose size we can cheaply dynamically query.  If we can see the call to malloc(N), using N is easy.  Some allocation libraries provide a means to query the size of an allocation.

Page Align Boundaries
  If we know the page size, we can compute a safe region from the last guaranteed access rounded up to the nearest increment of page size.  For a properly aligned access stream, that's enough to prove safety of the vectorized form.  (See also approach below.)

Speculation Safety
  The compiler already has extensive mechanism to prove speculation safety of memory accesses.  If we can prove either a) the original access stream doesn't fault in our desired iteration space for the vector loop or b) that a[i: i + VF-1] doesn't fault unless a[i] does, then we're good to vectorize.

TODO - Page Boundary Generalized, and Exit Predication
======================================================

..

  Open Topics
  - non-static exit counts
      predication - for instructions following exit - need blur operation
  - tail folding (e.g. exit predication + tricky exit lane computation)

    cases for data dependent exits
    - page alignemnt via loop nest (vector->scalar->vector)
    - page alignment via predication and dynamic stride
    - exit predication (e.g. sink to backedge)

  





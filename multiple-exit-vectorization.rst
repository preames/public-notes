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

* Auditing the vectorizer source and fixing a number of places where the exit was assumed to also be the latch for historical reasons.
* Extending the existing 'requireScalarEpilogue' mechanism to *unconditionally* branch to the epilogue loop.
* Adding "has a non-latch exit" as a reason to require a scalar epilogue.

Worth noting is that this transform only works when we can compute a precise trip count for the original scalar loop.  Thankfully, SCEV has a bunch of infrastructure for that already and the vectorizer gets to implicitly rely on it.  It is worth noting that SCEV is only able to analyze loop exits which dominate the latch.  As a result, the vectorizer is also limited to vectorizing loops where all exits dominate the latch.

The Mechanics of Multiple Exits
-------------------------------

As described over in my generic `multiple exit loop notes <https://github.com/preames/public-notes/blob/master/llvm-loop-opt-ideas.rst#cornercases>`_, there's generalization needed to support multiple exits and in particular, exit blocks shared by multiple exiting blocks.

In this particular case, I did some prework in af7ef895d, handled everything except shared exit blocks with LCSSA phis in e4df6a40dad, and finished the generalization in 9f61fbd.


Open Topics
-----------

This section would be titled "future work", but at the moment, I'm not planning to continue working in this area.  I achieved my primary objective, and don't have any incentive to push this further.

Currently, only loops with entirely statically analyzable exits are supported.  Analyzable specifically means that SCEV's `getExitCount(L, ExitingBB)` returns a computable result.

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

It's worth noting that without the call to `bar()` in the above, SimplifyCFG will happily convert that loop exit into `if (cond() && cond2())` which is enough to let us analyze the upper bound of the exit assuming only `cond2()` is analyzable, and the exact trip count if both conditionals are.  It's not clear how common examples with `bar()` actually are.

Data dependent exits
====================

If we have exits which dominate the latch, but are not analyzable, we can sometimes form predicates which allow us to vectorize (e.g. widen operations) anyways.  Example:

.. code::

   // Classic b[a[i]] reduction with a range check on 'b'.
   loop {
     x = a[i];
     if (x < N) break;
     sum += b[x];
     i++;
   }

To highlight why this is hard, imagine that `a` is exactly one element long, and the range check fails on that first iteration.  Now align our one element `a` array such that `a[1]` would live on another page which would fault on access.
     
Let's enumerate some cases we could handle without solving the "general" problem.  All of these share a common flavor; we need to identify a precise runtime bound for a non-faulting access.  Once we have that, we can either:

* Clamp the iteration space of the vectorized loop to the umin of the otherwise computable trip count and our safe region.  In this case, our vectorized loops run only up to `a`.
* Generate a predicate mask for each load which is independent of the loop CFG and depends solely on the safe region information.

Either way, we can ensure that either `a[1]` doesn't execute, or that if it does, hardware predication masks the fault.

Statically Known Array Sizes
  If both `a` and `b` are statically sized (e.g. allocas, globals, etc..), we can form trivial bounds.

Dynamically Known Array Sizes
  We can generalize the former for any allocation whose size we can cheaply dynamically query.  If we can see the call to malloc(N), using N is easy.  Some allocation libraries provide a means to query the size of an allocation.

Page Align Boundaries
  If we know the page size, we can compute a safe region from the last guaranteed access rounded up to the nearest increment of page size.  For a properly aligned access stream, that's enough to prove safety of the vectorized form.  (See also approach below.)

Speculation Safety
  The compiler already has extensive mechanism to prove speculation safety of memory accesses.  If we can prove either a) the original access stream doesn't fault in our desired iteration space for the vector loop or b) that a[i: i + VF-1] doesn't fault unless a[i] does, then we're good to vectorize.

The General Case
================
  
Let's move on to approaches to the general problem.  There are two options I know of:

* Vectorize within a page, but not at the boundary.
* Exit predication

**Page Boundary Handling**

Starting with the first, let's introduce a new simpler example:

.. code::

   loop {
     if (cond(i)) break;
     sum += a[i];
     i++;
   }

If we know nothing about the bounds of the memory object `a`, and only know that `cond()` is vectorizeable without faulting,  we can still run the vector code if we're sufficiently far from a page boundary.  We can exploit this by forming one vector loop and one scalar loop, and branching between them based on distance from page boundary.  Here's an example of what that might look like:

.. code::

   // For simplicity, assume we're working with byte arrays so that
   // ElementSize doesn't need to appear in these expressions.
   loop {
     // vector loop
     while (i % PageSize < (PageSize - VF)) {
       pred = cond(i, i+VF-1)
       x = a[i, i+VF-1]
       x = pred ? x : 0
       sum = add_reduce(x)
       if (!allof(pred))
         goto actual_exit
       i += VF;
     }
     iend = i + 2*VF;
     while (i < iend) {
       if (cond(i)) break;
       sum += a[i];
       i++;
     }
  }

The challenge with this approach is a) the code complexity, b) the generated code size, and c) the fact that the portion of time in the vector loop drops sharply with the number of memory objects being accessed.  (The latter comes from the fact that we must run the scalar loop if *any* access is close to page boundary, and as you add accesses, the probably of running the vector loop decreases with roughly ((PageSize-VF)/PageSize)^N.)

I wrote the example above without the generally required scalar epilogue loop.  You can merge the two scalar loops which helps cut down the code size, at cost of further implementation complexity.

Another approach to the above is to use additional predication as opposed to the scalar loop.  In that formulation, our vector loop looks something like the following:

.. code::

   // For simplicity, assume we're working with byte arrays so that
   // ElementSize doesn't need to appear in these expressions.
   loop {
     pred1 = ivec % PageSize < (PageSize - VF)
     pred2 = cond(i, i+VF-1)
     pred = pred1 & pred2
     x = a[i, i+VF-1] masked by pred1
     x = pred ? x : 0
     sum = add_reduce(x)
     if (!allof(pred2))
       goto actual_exit
     if (allof(pred1))
       ivec += VF;
     else
       ivec += PageSize - ivec % PageSize;
   }

That code is very confusing, so let me try to explain what we're doing here.  We've added an addition predicate for the load to mask off any lanes past the end of the current page.  Then we advance the vector loop either by VF if we're not near a page boundary, or to the start of the next page if we were.  The result here is a vector loop which naturally aligns to the page boundary on the first one it encounters.

This form reduces code complexity and code size, at the cost of additional predication.  It does nothing about the fraction of time spent running full vector widths as the number of accesses increase though.

One LLVM specific note on this approach.  LLVM's dereferenceability reasoning is currently at the abstract memory object level, not the physical level.  Before implementing anything that leveraged page boundary information, we'd need to untangle some nasty problems around the definition of ptrtoint and assumes about the meaning of dereferenceability.

**Exit Predication**

The second major alternative is form predicates directly from the exit conditions themselves.  It's really tempting to think these exit predicates are only needed by accesses below the original exit in program order, but this is not true.  If we go back to our previous range checked b[a[i]] example, we need a predicate for lane 1 of the load from a which depends on the result from a[0].  Obviously, that is not, in general, possible.

Despite this impossibility result, the technique is frequently useful.  Consider the example:

.. code::

   loop {
     if (f(i))
       break;
     sum = a[i];
     i++;
   }

There's lots of cases where `f(i:i+VF-1)` is cheaply computable.  Take for example `f = x < N` where the vectorized form is simply `f(ivec) = ivec < splat(N)`.  Or wait, is it?

A careful reader will note that the vectorization above is only correct if i+VF-1 is always greater than i - that is, i does not overflow in the vectorized loop.  To account for overflow, we'd have to compute each lane and then "smear" any zero lane through all following lanes.  The vectorized form looks roughly like this:

.. code::

   loop {
     pred = f(i:i+vf-1)
     pred = smear_right(pred)
     x = a[i] masked by pred;
     sum = add_reduce(pred ? x : 0)
     i += VF;
     if (!allof(pred))
       break;
   }


If you restrict the function `f` above to the functions that SCEV can analyze trip counts for, this technique is basically the tail folding (e.g. predication) equivalent to the requires scalar epilogue approach implemented.  I'm unsure if the additional generality available in `f` functions which are not analyzeable by SCEV is interesting or not.  Maybe for IVs which do actually overflow?  The current SCEV logic is pretty limited in that case, but exploiting that in the vectorizer would also take a pretty major rewrite.

An alternate description of this transform would phrase it as access sinking.  Conceptually, we're trying to sink all accesses into the latch block.  If we can do that, we can form a vector predicate for all the exit conditions which are not data dependent.  I believe the two formulations to be a dual, though the sinking form makes it much more obvious how non-latch dominating exits might be handled.  (Though profitability of that general case is a truely open question.)

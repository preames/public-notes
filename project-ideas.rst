.. header:: This is a collection of random ideas for small projects I think are interesting, and would in theory love to work on someday.  Feel free to steal anything here which inspires you!

-------------------------------------------------
Free! Project Ideas
-------------------------------------------------

.. contents::

Missing Opt Reduction
---------------------

With any form of super-optimizer, one tricky bit is turning missing optimizations in large inputs into small self contained test cases.  (i.e. making the findings actionable for compiler developers)  Automated reduction tools are generally good at reducing failures (i.e. easy interestness tests).  A tool which wrapped a super optimizer and simply returned an error code if the super optimizer could find a further optimization in the input would allow integration with e.g. bugpoint and llvm-reduce.  Bonus points if the wrapper passed through options to the underlying tool invocation (e.g. see opt-alive) so that a test can be entirely self contained.

opt-alive for NFC proofs
------------------------

Many changes are marked NFC.  These are generally a candidate for differential proofs, and the opt-alive tool (from alive2) seems to be a good fit here.  Could very well be enough to prove many NFCs were in fact NFCs (for at least some build environment).

SCEV Based Array Language
--------------------------

Many places in LLVM need to be able to reason about memory accesses spanning multiple iterations of a loop (e.g. loop-idiom, vectorizer, etc..).  SCEV gives an existing way to model addresses and values stored (as separate SCEVs), but we don't really have a mechanism to model the memory access as a first class object.

Having "store <i64 0,+,1> to <%obj,+,8>" as a first class construct allows generalizations of existing transforms.  For example: A two accesses of the form "store <i32 0> to <%obj,+, 8>" and "store <i32 0> to <%obj+4,+, 8>" can be merged into a single "store <i64 0> to <%obj,+, 8>", enabling generalize memset recognition.

Looking at ajacent loops, knowing that two stores overlap (i.e. a later loop clobbers the same memory), allows iteration space reductions for the first.

This may combine in interesting ways with MemorySSA.  I have not looked at that closely.

Focus on optimizing outparams
-----------------------------

The example below (originally written in the context of https://reviews.llvm.org/D109917), reveals some interesting missed LLVM optimizations.

.. code::

   int foo();

   extern int test(int *out) __attribute__((noinline));
   int test(int *out) {
     *out = foo();
     return foo();
   }

   int wrapper() {
     int notdead;
     if (test(&notdead))
       return 0;
   
     int dead;
     int tmp = test(&dead);
     if (notdead)
       return tmp;
     return foo();
   }

Here's the ones I've noticed so far:

* Failure to infer writeonly argument attribute.  I went ahead and posted https://reviews.llvm.org/D114963, but there's a bunch of follow up work needed.
* Failure to sink the second call to dead (i.e. the motivating review above).
* Failure to color allocas and reuse same alloca/variable for outparams to both calls.
* Oppurtunity to promote outparam to struct return in dso local copy with shim.  (Not sure this is generally profitable through.)
* Oppurtunity to reduce lifetime.start/end scope around 'notdead' alloca.  You can think of this as part of coloring, or as a separate canonicalization step.
* Missed oppurtunity for tailcall optimization in final call to foo() in wrapper().  Similiar for final call to foo() in test()

This is a DRAFT of a RFC I'm considering sending to llvm-dev.  The current status is more an attempt to organize thoughts than an actually proposal.  

RFC: Decomposing deref(N) into deref(N) + nofree
-------------------------------------------------

TLDR: ...

The Basic Problem
==================

We have a long standing semantic problem with the way we define dereferenceability facts which makes it difficult to express C++ references, or more generally, dereferenceability on objects which may be freed at some point in the program. The current structure does lend itself well to memory which can't be freed.  As discussed in detail a bit later, we want to seemlessly support both use cases.

The basic statement of the problem is that a piece of memory marked with deref(N) is assumed to remain dereferenceable indefinitely.  For an object which can be freed, marking it as deref can enable unsound transformations in cases like the following::

  o = deref(N) alloc();
  if (c) free(o)
  while(true) {
    if (c) break;
    // With the current semantics, we will hoist o.f above the loop
    v = o.f;
  }

Despite this, Clang does emit the existing dereferenceable attribute in some problematic cases.  We have observed miscompiles as a result, and optimizer has an assortment of hacks to try not to be too agreesive and miscompile too widely. 

Haven't we already solved this?
===============================

This has been discussed relatively extensively in the past, included an accepted review (https://reviews.llvm.org/D61652) which proposed splitting the dereferenceable attribute into two to adress this.  However, this change never landed and recent findings reveal that we both need a broader solution, and have an interesting oppurtunity to take advantage of other recent work.

The need for a broader solution comes from the observation that deref(N) is not the only attribute with this problem.  deref_or_null(N) is a fairly obvious case we'd known about with the previous proposal, but it was recently realized that other allocation related facts have this problem as well.  We now have specific examples with allocsize(N,M) - and the baked in variants in MemoryBuiltins - and suspect there are other attributes, either current or future, with the same challenge.

The oppurtunity comes from the addition of "nofree" attribute.  Up until recently, we really didn't have a good notion of "free"ing an allocation in the abstract machine model.  We used to comingle this with our notion of capture, and sometimes even aliasing.  (i.e. We'd assume that functions which could free must also capture and/or write.)  With the explicit notion of "nofree", we have an approach available to us we didn't before.

The Proposal Itself
====================


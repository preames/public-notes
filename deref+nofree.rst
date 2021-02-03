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

The basic idea is that we're going to redefine the currently globally scoped attributes (deref, deref_or_null, and allocsize) such that they imply a point in time fact only and then combine that with nofree to recover the previous global semantics.  

More specifically:

* A deref attribute on a function parameter will imply that the memory is dereferenceable for a specified number of bytes at the instant the function call occurs.  
* A deref attribute on a function return will imply that the memory is dereferenceable at the moment of return.
* A deref(N) argument to a function with the nofree function attribute is known to be globally dereferenceable within the scope of the function call.  
* An argument which is both deref(N) and nofree is known to be globally dereferenceable within the scope of the function call.  (ATTN: The current nofree spec is vague about whether the object can be freed through another copy of the pointer?)
* A return which is both deref(N) and nofree is known to be globally dereferenceable from the moment or return onward.  There is no scoping here.  This requires that we extend the nofree attribute to allow return values to be specified with "never freed from this point onwards" semantics.  

The items above are described in terms of deref(N) for ease of description.  The other attributes are handle analogously.

Use Cases
=========

**C++ References** -- A C++ reference implies that the value pointed to is dereferenceable at point of declaration, and that the reference itself is non-null.  Of particular note, an object pointed to through a reference can be freed without introducing UB.  

::
  class A { int f; };
  
  void ugly_delete(A &a) { delete &a; }
  ugly_delete(*new A());
  
  void ugly_delete2(A &a, A *a2) {
    if (unknown)
      // a.f can be *proven* deref here as it's deref on entry,
      // and no free on path from entry to here.
      x = a.f;
    delete a2; 
  }
  auto *a = new A();
  ugly_delete2(*a, a);
  
  A &foo() {...}
  A &a = foo();
  if (unknown)
    delete b;
  // If a and b point to the same object, a.f may not be deref here
  if (unknown2)
    a.f;


**Garbage Collected Objects (Java)** -- LLVM supports two models of GCed objects, the abstract machine and the physical machine model.  The later is essentially the same as that for c++ as deallocation points (at safepoints) are explicit.  The former has objects conceptually live forever (i.e. reclaimation is handled outside the model).  

::
  class A { int f; }
  
  void foo(A a) {
    ...
    // a.f is trivially deref anywhere in foo
    x = a.f;
  }
  
  A *a = new A();
  ...
  // a.f is trivially deref following it's definition
  x = a.f;
  
  A foo();
  a = foo();
  ...
  // a.f is (still) trivially deref 
  x = a.f;

Migration
==========

Existing bytecode will be upgraded to the weaker non-global semantics.  This provides forward compatibility, but does loose optimization potential.

Frontends which want the point in time semantics should emit deref and not nofree.

Frontends which want the global semantics should emit nofree where appropriate.  In particular, GCed languages using the abstract machine model should tag every function as nofree.  

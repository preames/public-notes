.. header:: This is a DRAFT of a RFC I'm considering sending to llvm-dev.  The current status is more an attempt to organize thoughts than an actually proposal.  

-------------------------------------------------
RFC: Decomposing deref(N) into deref(N) + nofree
-------------------------------------------------

TLDR: ...

.. contents::

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
* We will then use the point in time fact combined with other information to drive inference of the global facts.  See below for a sampling of inference rules.

Inference cases:

* A deref(N) argument to a function with the nofree and nosync function attribute is known to be globally dereferenceable within the scope of the function call.  We need the nosync to ensure that no other thread is freeing the memory on behalf of the callee in a coordinated manner.
* A deref argument to a function in a module with the "gc.abstract-model" flag is known to be globally dereferenceable as the program globally can not contain deallocation.  (Until after lowering at which point the flag is removed.)
* An argument with the attributes deref(N), noalias, and nofree is known to be globally dereferenceable within the scope of the function call.  This relies on the fact that free is modeled as writing to the memory freed, and thus noalias ensures there is no other argument which can be freed.  (See discussion below.)

The items above are described in terms of deref(N) for ease of description.  The other attributes are handle analogously.

**Explanation**

The "deref(N), noalias, + nofree" argument case requires a bit of explaination as it involves a bunch of subtleties.

First, the current wording of nofree argument attribute implies that the callee can not arrange for another thread to free the object on it's behalf.  This is different than the specification of the nofree function attribute.  There is no "nosync" equivelent for function attributes.

Second, the noalias argument attribute is subtle.  There's a couple of sub-cases worth discussing:

* If the noalias argument is written to (and free is modeled as a write), then it must be the only copy of the pointer passed to the function and there can be no copies pass through memory.
* If the noalias argument is only read from, then there may be other copies of the pointer.  However, all of those copies must also be read only.  If the object was friend through one of those other copies, then we must have at least one write copy and having the noalias on the read copy was undefined behavior to begin with.

Essentially, what we're doing with noalias is using it to promote a fact about the pointer to a fact about the object being pointed to.  

**Result**

It's important to acknowledge that with this change, we will loose the ability to specify global dereferenceability of arguments and return values in the general case.  We believe the current proposal allows us to recover that fact for all interesting cases, but if we've missed an important use case we may need to iterate a bit.  

We've discussed a few alternatives (below) which could be revisited if it turns out we are missing an important use case.

Use Cases
=========

**C++ References** -- A C++ reference implies that the value pointed to is dereferenceable at point of declaration, and that the reference itself is non-null.  Of particular note, an object pointed to through a reference can be freed without introducing UB.  

.. code:: c++

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

.. code:: java

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
  
**Rust Borrows** -- A rust reference argument (e.g. "borrow") points to an object whose lifetime is guaranteed to be longer than the reference's defining scope.  As such, the object is dereferenceable through the scope of the function.  Today, rustc does emit a dereferenceable attribute using the current globally dereferenceable semantic.  

.. code:: rust

  pub fn square(num: &i32) -> i32 {
    num * num
  }
  square(&5);

  // a could be noalias, but isn't today
  pub fn bar(a: & mut i32, b: &i32) {
    a = *a * b
  }

  bar(i32::new(5), 2);
  
  // At first appearance, rust does not allow returning references.  So return
  // attributes are not relevant.  This seems like a major language hole, so this
  // should probably be checked with a language expert.

Migration
==========

Existing bytecode will be upgraded to the weaker non-global semantics.  This provides forward compatibility, but does loose optimization potential.

Frontends which want the point in time semantics should emit deref and not nofree.

Frontends using the GC abstract machine model (in which deallocation is UB) should emit the "gc.abstract_model" flags.

Rustc should emit noalias where possible.  In particular, 'a' in the case 'bar' above is currently not marked noalias and results in lost optimization potential as a result of this change.

Frontends which want the global semantics should emit noalias, nofree, and nosync where appropriate. If this is not enough to recover optimizations in common cases, please follow up on llvm-dev.  

Alternative Designs
===================

Extend nofree to object semantics
----------------------------------

The nofree argument attribute current describes whether an object can freed through some particular copy of the pointer.  We could strength the semantics to imply that the object is not freed through any copy of the pointer in the specified scope.

Doing so greatly weakens our ability to infer the nofree property.  The current nofree property when combined with capture tracking in the caller is enough to prove interest deref facts over calls.  We don't want to loose the ability to infer that.

Add a separate nofreeobj
------------------------

Rather than change nofree, we could add a parallel attribute with the stronger object property.  This - combined with deref(N) as a point in time fact - would be enough to recover the current globally deferenceable semantics.  

The downside of this proposal is a) possible overkill, and b) the "ugly" factor of having two similiar but not quite identical attributes.

Add an orthonganal attribute to promote pointer facts to object ones
--------------------------------------------------------------------

To address the weakness of the former alternative, we could specify an attribute which strengthens arbitrary pointer facts to object facts.  Examples of current pointer facts are attributes such as readonly, and writeonly.  

This has not been well explored; there's a huge possible design space here. 




.. header:: This is a DRAFT of a RFC I'm considering sending to llvm-dev.  The current status is more an attempt to organize thoughts than an actually proposal.  

-------------------------------------------------
Defining Capture
-------------------------------------------------

TLDR: ...

.. contents::

Terminology
------------
As with any property, there are both may and must variations.  Unless explicitly stated otherwise, we assume henceforth that "captured" means "may be captured" or "potentially captured", and that "nocapture" means "definitely not captured."

Candidate Definition
---------------------

A captured object is one whose contents or address can be observed by an external party which controls the implementation of externally defined functions, and can call back into the module through any external exposed entry point (potentially concurrently).  The external party is restricted from "guessing" the addresses of uncaptured objects.  Once captured, an object remains captured indefinitely.

Some specific examples of captured objects:

* A global variable with a linkage other than private is captured.
* An object passed to an external function as an argument is captured.
* An object returned by a function with non-private linkage is captured.
* A memory object reachable from another captured object is captured.
* A memory object which was *previously* reachable (even if transiently so) from a captured object remains captured.
* A memory object whose address could be propagated to a captured location is captured if there exists a non-private function which when invoked could perform said propagation.  (Remember, our externally party is both adversarial and running concurrently, so it can arrange perfect timing attacks as needed.)

Corollaries
-----------

An object which is eventually captured (i.e. visible to our external observer) may not yet have been captured at a particular program point.  We say that such objects as "nocapture before Ctx" where "Ctx" is the program point being discussed.  For instance, all static allocs start as uncaptured, and while the allocation may be eventually captured, that doesn't change the fact the object was nocapture before that point.

A capturing operation is one which exposes a previously uncaptured object to our external observer.

An object is uncaptured in a particular scope if the object was not previously captured before that scope, and no action performed within the scope is a capturing operation.  In particular, note that there's nothing preventing an enclosing scope from capturing the object provided that the capturing operation occurs strictly after the end of our inner scope.

FOR DISCUSSION: The last point differs from our currently implementation.  We'd consider an object captured in the current scope if returned.  We could phrase this as simple conservatism, but is there something deeper we're missing?

Exploratory Examples
--------------------

Let's start with a trivial example:

.. code:: c++

  void foo() {
    X* o = new X();
    o.f = 5;
    delete o;
  }

Object o is nocapture both globally and in the scope of foo.  

Leaking the object doesn't change that.

.. code:: c++

  void foo() {
    X* o = new X();
    o.f = 5;
  }

Adding a self referencial cycle doesn't change that.

.. code:: c++

  void foo() {
    X* o = new X();
    o.f = o;
    delete o;
  }

Scopes
=======

If we return an object, that object is captured if the function is not private.  So

.. code:: c++

  private_linkage X* wrap_alloc() {
    return new X();
  }

doesn't capture X, but

.. code:: c++

  X* wrap_alloc() {
    return new X();
  }

does.  Note that in both cases, the allocation is nocapture within the scope of wrap_alloc.

.. code:: c++

  private_linkage X* wrap_alloc() {
    return new X();
  }
  void foo() {
    X* o = wrap_alloc();
    o.f = 5;
    delete o;
  }

In this example, the allocation is uncaptured globally, and in both functions.

Object Graphs
=============

Moving on, let's consider connected object graphs.  

.. code:: c++

  void foo() {
    X* o1 = new X();
    X* o2 = new X();
    o1.f = o2;
    o2.f = o1;
  }

In this example, both o1 and o2 are nocapture.

If any object is observable, then all objects reachable through that object are captured.  

.. code:: c++

  X* foo() {
    X* o1 = new X();
    X* o2 = new X();
    o1.f = o2;
    o2.f = o1;
    return o1;
  }
  


Transient Captures
==================

.. code:: c++

  private_linkage int X;
  int* Y;

  void oops() {
    Y = &X;
    Y = nullptr;
  }

In this example, both X and Y are captured.  Our external observed can arrange oops to execute (since it's an external function) and read the address of X between the two writes.

This does nicely highlight that the optimizer can refine this program from one which captures X into one which doesn't by running dead store elimiantion.  As such, it's important to note that capture statements apply to the program at a moment in time.

Capture vs Lifetime
===================

.. code:: c++

  int* Y;

  void foo() {
    Y = new X();
    free(Y);
    Y = nullptr;
  }

In this example, Y has been captured.  Criticially, the memory object associated with the particular instance of X remains captured even once deallocated.  While the contents of said object are no longer defined, the address thereof continues to exist and may be validly used.

It's worth highlighting one counter intuitive implication.  If our adverserial observer calls this routine twice, a reasonable memory allocation may reuse the same physical memory for both instances of X.  This does not change the fact that conceptually these are two distinct memory objects.  Immediately before the store to Y on the second invocation, the first object may be captured (and deallocated) while the second one is not yet captured.  Even though they share the same address.

FOR DISCUSSION - I think this implies we need to tweak the definition slightly.  In particular, I think we need to incorporate something which references the based on rules to make access through the first copy UB, or we seem to have captured both (since per the proposed definition the address captures.)

(This discussion is not meant to be authorative on explaining the semantics of deallocation, for details, see the relevant section of langref.)


Draft LangRef Text
------------------

nocapture argument attribute
============================

If we have a pointer to an object which has not yet been captured passed to a nocapture argument of a function, we know that the callee will not perform a capturing operation on this argument.  Note that this only restricts operations by the callee performed on this argument.  If a separate copy of the pointer is passed through an argument or memory, the callee may capture or store aside in an unknown location that copy of the pointer.

In addition to the capture fact just stated, a nocapture argument attribute also provides an additional "trackability" fact.  If before the call, the callee is aware of all copies of a pointer, and all copies of the pointer passed to the callee are passed through nocapture arguments, then after the call, the caller can assume that no new copies of the pointer have been created.  (Even if those copies are in uncaptured locations.)

Note that this definition says nothing about what the callee might do if the object was already captured before the call.

nofree function attribute
=========================

TODO: Wording here is incompatible with global capture definition.  Need something finer grained - maybe escape?

From langref: "As a result, uncaptured pointers that are known to be dereferenceable prior to a call to a function with the nofree attribute are still known to be dereferenceable after the call (the capturing condition is necessary in environments where the function might communicate the pointer to another thread which then deallocates the memory)."

The problem with this is that an uncaptured copy in a private global variable still allows another thread to free it.

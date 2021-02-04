
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
An object is said to be captured in all scopes in which it's contents are observable.  It is said to be nocaptured in all outer scopes in which it's contents can not be observed in this scope, or any outer scope thereof.

There's a couple important points to this definition:

* **Scope** -- The only scopes currently defined in LLVM IR are function scopes.  As such, all capture statements are implicitly attached to some function.
* **Observation** -- This aspect allows stores to locations which are never read, and other uses which would appear to capture the pointer so long as the result is unobserved.  This prevents otherwise well defined transforms such as DSE from refining a nocapture object into a captured one.
* **Refinement** --  As with many other properties in LLVM IR, well defined transforms can refine a program into one with fewer legal behaviors.  The intention of the definition is to allow refinement from captured to nocapture, but not the other way around.  

Exploratory Examples
--------------------

Let's start with a trivial example:

.. code:: c++

  void foo() {
    X* o = new X();
    o.f = 5;
    delete o;
  }

Object o is nocapture in the scope of foo.  

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

As a notational conviance, further examples are listed without an explicit deletion to emphasize that the scope it tied to last observation, not allocation or deletion.  It is worth noting that it follow from the definition of deletion in most languages there can be no (defined) observations past deletion.

Scopes
=======

Next, let's consider an example which introduces multiple scopes:

.. code:: c++

  X* wrap_alloc() {
    return new X();
  }
  void foo() {
    X* o = wrap_alloc();
    o.f = 5;
    delete o;
  }

In this example, the allocation is captured in both foo and wrap_alloc, but for different reasons.  For wrap_alloc, the pointer is redundant and potentially observable outside it's scope.  For foo, we don't have the knowledge that the return value of wrap_alloc hasn't been captured inside wrap_alloc in a way observable outside of it.  The optimizer would in practice infer that fact, leading to out first instance of refinement.

.. code:: c++

  X* noalias wrap_alloc() {
    return new X();
  }
  void foo() {
    X* o = wrap_alloc();
    o.f = 5;
    delete o;
  }

With the additional fact, we can now infer that the allocation is nocapture in foo, but not in wrap_alloc.

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

In this example, both o1 and o2 are nocapture in the scope of foo.  

If any object is observable in a parent scope, then all objects reachable through that object are observable in that scope.  

.. code:: c++

  X* foo() {
    X* o1 = new X();
    X* o2 = new X();
    o1.f = o2;
    o2.f = o1;
    return o1;
  }

  void bar() {
    X* o = foo();
  }

In this case, we see that both allocations are captured in foo, but nocapture in bar.  In the following example, o1 is nocapture in both foo and bar, while o2 is only nocapture in bar.

.. code:: c++

  X* foo() {
    X* o1 = new X();
    X* o2 = new X();
    o1.f = o2;
    return o2;
  }

  void bar() {
    X* o = foo();
  }



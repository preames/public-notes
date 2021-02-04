
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

Let's start with a trivial example::

.. code:: c++

  void foo() {
    X* o = new X();
    o.f = 5;
    delete o;
  }

Object o is nocapture in the scope of foo.  Next, let's consider an example which introduces multiple scopes::

.. code:: c++
  
  X* wrap_alloc() {
    return new X();
  }
  void foo() {
    X* o = wrap_alloc();
    o.f = 5;
    delete o;
  }
  

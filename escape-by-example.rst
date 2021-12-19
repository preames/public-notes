-------------------------------------------------
Escape Analysis Optimizations by Example
-------------------------------------------------

This page includes a list of example optimizations which leverage some variant of escape analysis.  This very deliberately does not try to formalize what we mean by "escape" or "capture"; doing so is hard.  Instead, we'll take a pretty informal view with the semantics of our example language being whatever we need to demonstrate an idea.  :)

.. contents::

Purning Dead Allocations
------------------------

.. code::
   
  void test() {
    X* o = new X();
    delete o;
  }
  == optimizes to ==>
  
  void test() {}

Removing Dead Stores
------------------------

If nothing can observe a store, it's dead.  

.. code::
   
  void test() {
    X* o = new X();
    ..(non capturing)..
    o->f = 5;
    delete o;
  }
  == optimizes to ==>
  
  void test() {
    X* o = new X();
    ..(non capturing)..
    delete o;
  }

Write Deferral
--------------

We can sink to the point a store might be observed

.. code::
   
  void test() {
    X* o = new X();
    o->f = 5;
    if (...) return;
    capture(o);
  }
  == optimizes to ==>
  
  void test() {
    X* o = new X();
    if (...) return;
    o->f = 5;
    capture(o);
  }

Note that there's an interesting scheduling profitability question here when the first point of possible capture is a hotter block then the original initialization.  Sinking into the loop in the following example is probably not desirable.

.. code::

   void test() {
    X* o = new X();
    o->f = 5;
    loop {
      capture(o);
    }
  }

Particularly interesting variants of this come from observing that calls to other functions can not interact with an unescaped object.

.. code::
   
  void test() {
    X* o = new X();
    o->f = 5;
    foo()
    capture(o);
  }
  == is equavalent to ==>
  
  void test() {
    X* o = new X();
    foo()
    o->f = 5;
    capture(o);
  }

Another way to say the same is that an unescaped object can not alias a call to another function.


Allocation Reuse
----------------

.. code::

  void test() {
    loop {
      X* o = new X();
      ..(non capturing)..
      free(o);
    }
  }
  == optimizes to ==>
  
  void test() {
    X* o = new X();
    loop {
      ..(non capturing)..
    }
    free(o);
  }

Another variant of the same idea...

.. code::

  void test() {
    loop {
      X* o = new X();
      ..(non capturing)..
      free(o);
      X* o2 = new X();
      ..(non capturing)..
      free(o2);
    }
  }
  == optimizes to ==>
  
  void test() {
    X* o = new X();
    ..(non capturing)..
    X* o2 = o;
    ..(non capturing)..
    free(o2);
  }


Lifetime Reduction
------------------

.. code::

  void test() {
    X* o = new X();
    ..(non capturing)..
    o.f = 6;
    use_noncapture(o)
    ..(non capturing)..    
    free(o);
  }
  == optimizes to ==>
  
  void test() {
    ..(non capturing)..
    X* o = new X();
    o.f = 6;
    use_noncapture(o)
    free(o);
    ..(non capturing)..    
  }

.. code::

  void test() {
    o = alloca X
    ..(non capturing)..
    o.f = 6;
    use_noncapture(o)
    ..(non capturing)..    
  }
  == optimizes to ==>
  
  void test() {
    o = alloca X
    ..(non capturing)..
    lifetime.begin(o)
    o.f = 6;
    use_noncapture(o)
    lifetime.end(o)
    ..(non capturing)..    
  }

Allocation Sinking
------------------

This is a variant of the former, but is often useful for discussion purposes.

.. code::

  void test() {
    X* o = new X();
    if (...)
      capture(o);
  }
  == optimizes to ==>
  
  void test() {
    if (...) {
      X* o = new X();
      capture(o);
    }
  }

Another variant of the same..
  
.. code::

  void test() {
    X* o = new X();
    may_throw_or_hang();
    use(o);
  }
  == optimizes to ==>
  
  void test() {
    may_throw_or_hang();
    X* o = new X();
    use(o);
  }



Inequality/NoAlias
------------------

An unescaped object can't be equal to a value which must have escaped.  Nor can it alias.

.. code::

  void test() {
    X* o = new X();
    if (o == *g) {}
    ...
  }
  == optimizes to ==>
  
  void test() {
    X* o = new X();
    if (false) {}
    ...
  }

Allocation Merging
----------------

.. code::

  void test() {
    loop {
      X* o = new X();
      X* o2 = new X();
      ..(non capturing)..
      free(o);
      free(o2);
    }
  }
  == optimizes to ==>
  
  void test() {
    X[] big = new X[2];
    X* o = big[0]
    X* o2 = big[1]
      ..(non capturing)..
    free(big);
  }

Another variant...

.. code::

  void test() {
    if (...) {
      X* o = new X();
      ..(non capturing)..
      free(o);
    } else {
      X* o2 = new X();
      ..(non capturing)..
      free(o2);
    }
  }
  == optimizes to ==>
  
  void test() {
    X* o = new X();
    if (...) {
      ..(non capturing)..
    } else {
      ..(non capturing)..
    }
    free(o);
  }


Allocation Coloring
-------------------

Written with non-overlapping live-ranges to illustrate distinction from allocation reuse and merging.  Reuse and merging are strictly profitable, this one might not be based on relative frequencies.  It saves heap space/churn if both paths are taken, but at the cost of an unneeded allocation if neither is.  Arguably, reuse and merging are sub-categories of coloring.

.. code::

  void test() {
    if (...) {
      X* o = new X();
      ..(non capturing)..
      free(o);
    }
    if (...) {
      X* o2 = new X();
      ..(non capturing)..
      free(o2);
    }
  }
  == optimizes to ==>
  
  void test() {
    X* o = new X();
    if (...) {
      ..(non capturing)..
    }
    if (...) {
      X* o2 = o
      ..(non capturing)..
    }
    free(o);
  }

Allocation Splitting
--------------------

Splitting is pretty much the inverse of coloring.  The basic idea is that we can split a single allocation into two or more if we can find a point during the original live range where the contents of the allocation are dead (either originally, or after optimizations such as SROA)..

.. code::
  
  void test() {
    X* o = new X();
    if (rare) {
      ..(non capturing)..
    }
    if (rare2) {
      ..(non capturing)..
    }
    free(o);
  }
  == optimizes to ==>
  void test() {
    if (rare) {
      X* o = new X();
      ..(non capturing)..
      free(o);
    }
    if (rare) {
      X* o2 = new X();
      ..(non capturing)..
      free(o2);
    }
  }

Note that write deferral described above can be thought of as doing allocation splitting when one of the allocations doesn't need to be explicitly materialized.

Tail Call Formation
-------------------

A particularly interesting version of lifetime reduction.

.. code::
  
  void test() {
    X* o = new X();
    ..(non capturing)..
    foo()
    free(o)
  }
  == optimizes to ==>
  void test() {
    X* o = new X();
    ..(non capturing)..
    free(o)
    // The call may now be eligable for tail call optimization
    foo()
  }

Store Insertion (e.g. loop promotion)
-------------------

In addition to removing stores, it's possible to *add* a store to an unexcaped object without worrying about whether another thread can observe the new write.

.. code::
  
  void test() {
    X* o = new X();
    for (0 to N) {
      if (...) break;
      o->f = 5;
      ..(non capturing)..
    }
    free(o)
  }
  == optimizes to ==>
  void test() {
    X* o = new X();
    for (0 to N) {
      if (...) break;
      ..(non capturing)..
    }
    o->f = ... appropriatedly selected value ...;
    free(o)
  }

Concurrency Downgrade
---------------------

.. code::
  
  void test() {
    X* o = new X();
    ..(non capturing)..
    o->f = 5 with release semantics..
    capture(o)
  }
  == optimizes to ==>
  void test() {
    X* o = new X();
    ..(non capturing)..
    o->f = 5 w/o ordering
    publication_fence(o)
    capture(o)
  }

The publication_fence is required because after downgrading the ordering of the original store, there's nothing preventing the last write to o from being reordered with a publishing store of o.  If that reordering is allowed, another thread can observe a value which wasn't possible in the original program.

Fence Elimination/Deferral
--------------------------

As a variation of the last, we can also eliminate fences whose only effect is to order writes to an unescaped object.  Such writes aren't visible to other threads by definition, so as long as we fence after the last and before the first possible capture, we're fine.

.. code::
  
  void test() {
    X* o = new X();
    o->f = 4
    release_fence
    o->f = 5
    release_fence
    capture(o)
  }
  == optimizes to ==>
  void test() {
    X* o = new X();
    o->f = 4
    o->f = 5
    release_fence
    capture(o)
  }

Subtely, we can't use a publication_fence here.  Unlike an ordered store, a fence might also be fencing unrelated memory locations.  We need a fence between any store which preceeded the example function, and the first following observable memory operation.


  

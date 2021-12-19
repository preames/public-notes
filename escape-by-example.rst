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

Written with non-overlapping liveranges to illustrate distinction from allocation reuse and merging.  Reuse and merging are strictly profitable, this one might not be based on relative frequencies.  It saves heap space/churn if both paths are taken, but at the cost of an unneeded allocation if neither is.  Arguably, reuse and merging are sub-categories of coloring.

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

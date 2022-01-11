-------------------------------------------------
Observable Allocations
-------------------------------------------------


.. contents::

Examples
========

.. code::

  free(malloc(8));
  ==>
  nop

.. code::

  malloc(0);
  ==>
  nullptr

.. code::

  free(realloc(o, N))
  ==>
  free(o);

.. code::

  o1 = realloc(o, 0)
  // (if o1's address is not captured)
  ==>
  free(o);
  o1 = nullptr;

.. code::

  free(new int())
  ==>
  unreachable
  
.. code::

  o = malloc(8);
  lifetime_end(o+4, 4)
  ==>
  o = malloc(4)

.. code::

  o = malloc(8);
  lifetime_end(o, 4)
  ==>
  o = malloc(4) - 4

.. code::

  if (o != nullptr) free(o)
  ==>
  free(o)

Other Allocation Properties
==========================

Nullability
-----------

.. code::

   allocate(N) == nullptr?

Zero Sided Allocations
----------------------

.. code::

   allocate(0) == allocate(0)?

Is the allocator required to return distinct addresses?  Or guaranteed to fail via exception or error-val on zero sized allocation?

Object Crossing Compares
-------------------------

.. code::

   allocate(N) + N == allocate(M)?

Is this well defined?

Distinct Heap/Stack/Globals
---------------------------

If the prior example is well defined, are there limits of which objects can be compared?

.. code::

   allocate(N) == &global_var?
   allocate(N) == &stack_var?

Which of these are well defined?

Guessed Pointers
----------------

.. code::

   allocate(N) == cast<pointer>(0xmyconstant)?

Is this well defined?

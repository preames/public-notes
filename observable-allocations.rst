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

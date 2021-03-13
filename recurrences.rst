  
-------------------------------------------------
Fun w/Recurrences in LLVM
-------------------------------------------------

This page is a mixture of a writeup on some recent work I've done around recurrences in LLVM, and a punch list for potential follow ups.  

.. contents::

Problem Statement
=================

A recurrence is simply a sequence where the value of f(x) is computable from f(x-1) and some constant terms.  I find `this definition <https://mathinsight.org/definition/recurrence_relation>_` useful.

Historically, LLVM has primarily used ScalarEvolution for modeling loop recurrences, but SCEV is rather specialized for add recurrences.  Over the years, we've grown a collection of one-off logic in a couple different places, mostly because pragmatic concerns about a) compile time of SCEV, and b) difficulty of plumbing SCEV through to all the places.

Notation
========

Skip this until one my examples doesn't make sense, then come back.

**<STart,Op,Step>** follows the convention SCEV uses for displaying add recurrences and generalizes for any Op.  <Start,Op,Step> expands to:

::

  %phi = phi i64 [%start, %entry], [%next, %backedge]
  ...
  %next = opcode i64 %phi, %step

For non-communative operators, I generally only use this notation for the form with %phi in the left hand side of the two operators.  Note that Step may not be loop invariant unless explicitly stated otherwise.

I will also sometimes use the notation f(x) = g(f(x-1)) where that's easier to follow.  In particular, I use that for the inverted forms of the non-communative operators.  You should assume that f(0) == Start unless explicitly said otherwise.

**LIV** stands for "loop invariant value" and is simply a value which is invariant in the loop refered do.

**CIV** stands for "canonical induction variable".  A canonical IV is the sequence (0,+,1).  (Or sometimes <1,+,1>.  Yes, I'm being sloppy about my off-by-ones.)

Fun w/Recurrences
=================

Integer Arithmetic
------------------

**ADD recurrences** are generally well covered by Scalar Evolution already.

**SUB recurrences** are generally canonicalized to add recurrences.  One interesting case is:

::
  %phi = phi i64 [%start, %entry], [%next, %backedge]
  ...
  %next = sub i64 %LIV, %phi

That is, f(x) = LIV - f(x-1).  This alternates between Start, and LIV - Start.  If we unrolled the loop by 2, we could eliminate the IV entirely.

Status: Unimplemented


A **mul recurrence** w/a loop invariant step value is a power sequence of the form Start*Step^CIV when overflow can be disproven.  (TODO: Does this hold with wrapping twos complement arithmetic?)   See my notes on `exponentiation in SCEV <https://github.com/preames/public-notes/blob/master/scev-exponential.rst>_` for ideas on what we could do here.  It's worth noting that the overflow cases may be identical to the cases we could canonicalize the shifts.  (TBD)

A **udiv/sdiv recurrence** w/a loop invariant step forms a sequence of the form Start div (Step ^ CIV) when overflow can be disproven.  Again, exponentiation?

Shift Operators
---------------

TBD - A bunch of work here on known bits, range info, and SCEV bits.


Bitwise Operators
-----------------

A **AND and OR recurrence** w/ a loop invariant step value stablize after the first iteration.  That is, anding (oring) a value repeatedly has no effect.  Thus

::

  %phi = phi i64 [%start, %entry], [%next, %backedge]
  ...
  %next = and i64 %phi, %LIV

Is equivalent to:

::
   
  %next = and i64 %start, %LIV
  ...
  %phi = phi i64 [%start, %entry], [%next, %backedge]
  ...

Status: Implemented in `D97578 <https://reviews.llvm.org/D97578>_` + existing LICM transform.

A **XOR recurrence** w/ a loop invariant step value will alternate between two values.  As such, there is a potential to eliminate the recurrence by unrolling the loop by a factor of two.

Status: Unimplemented.


Floating Point Arithmetic
--------------------------

In general, floating point is tricky because many operators are not commutative.

Most of the obvious options involve proving floating point IVs can be done in integer math.  I have some old patches pending review (`D68954 <https://reviews.llvm.org/D68954>_` and `D68844 <https://reviews.llvm.org/D68844>_`), but there's little active progress here.

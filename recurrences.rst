  
-------------------------------------------------
Fun w/Recurrences in LLVM
-------------------------------------------------

This page is a mixture of a writeup on some recent work I've done around recurrences in LLVM, and a punch list for potential follow ups.

.. contents::

Basic Problem
=============

A recurrence is simply a sequence where the value of f(x) is computable from f(x-1) and some constant terms.  I find `this definition <https://mathinsight.org/definition/recurrence_relation>_` useful.

Historically, LLVM has primarily used ScalarEvolution for modeling loop recurrences, but SCEV is rather specialized for add recurrences.  Over the years, we've grown a collection of one-off logic in a couple different places.

Fun w/Recurrences
=================

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



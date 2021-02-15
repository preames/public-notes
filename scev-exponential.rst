.. header:: This is a collection of notes on a topic that may someday make it into a proposed extension to LLVM's SCEV, but that I have no plans to move forward with in the near future.  

-------------------------------------------------

SCEV, shifts, and M^N as a primitive

-------------------------------------------------

.. contents::

Basic Idea
===========

SCEV currently does not have a first class representation for bit operators (lshr, ashr, and shl).  Particular special cases are represented with SCEVMulExpr and SCEVDivExpr, but in general, we fall back to wrapping the IR expression in a SCEVUnknown.

It's interesting to note that all shifts can be represented as LHS*2^N or LHS/2^N.  Unfortunately, we don't have a way to represent 2^M in SCEV for arbitrary N.

We've also run into cases before where power functions specialized for fixed values of N arise naturally when canonicalizing SCEVs or handling unrolled loops involving products or shifts.  As a result, commit 35b2a18eb96d0 added first class support in SCEVExpander for an optimized power emission.  (Leaving the internal representation unchanged.)

It's also interesting to note that a moderately wide family of non-add recurrences can be represented as an add recurrence multiplied by a power function.  For instance, <y,*,x> (my extended notation for a mul recurrence multiplying by x on every iteration) can be represented as y*x^<0,+,1).  The same idea can be extended to shl, ashr, and lshr, and some cases of udiv.

Obvious Alternatives
====================

Don't represent at all
----------------------

This is simply the status quo, possibly with some enhancements to handle obvious cases during construction and range analysis, but without changing the SCEV expression language itself.

Add explicit SCEVShlExpr, etc...
---------------------------------

This improves our ability to reason about the expressions, but doesn't get us the ability to reason about recurrences unless we add explicit SCEVShlRecExpr expressions as well.  











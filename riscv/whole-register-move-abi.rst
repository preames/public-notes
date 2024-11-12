------------------------------------------------------
ABI Implication of vill and whole vector register move
------------------------------------------------------

Background
----------

The vector specification supports a whole register move instruction
whose documented purpose is to enable register allocators to move
vector register contents around without needing to track ``VL`` or
``VTYPE``.

A `change was made to the specification <https://github.com/preames/public-notes/blob/master/riscv-spec-minutia.rst#whole-vector-register-move-and-vill>`_
which requires hardware to report a illegal instruction exception
if this instruction is executed with `vill` set.

Existing SW implementations - in particular LLVM and GCC - were
both implemented *before* this change was made, and implicitly
assume the prior behavior.

IMHO, an architecture which doesn't have an instruction to *just
unconditionally copy a dang register* is broken at a level which
just can't be saved, however we will probably have to workaround
this in software regardless.

See also discussion here: https://github.com/llvm/llvm-project/issues/114518

ABI Impact
----------

The current ABI says that ``VTYPE`` is *not* preserved across calls.
Note that in particular, this means that `vill` can be set across
any call boundary.

Before the above change, that was fine because a whole register
move did the sane thing regardless of vill.  After the above change
this means that any use of a whole register move betwen a call
boundary and the first dynamic vsetvli will potentially crash.

In theory, this is a huge problem.  However, up until recently
the defacto usage of the ABI was such that a valid `VTYPE` usually
did survive through call boundaries.

Unfortunately, Linux kernel 6.5 included a `patch <https://github.com/torvalds/linux/commit/9657e9b7d2538dc73c24947aa00a8525dfb8062c>`_ which sets
VILL=1 on all syscalls.  This is legal per the documented ABI (see below),
but has the effect of exposing the lurking problem.

The other case where this can be triggered in practice is via a
riscv vector intrinsic with a pass thru operand called early in the
execution of a program.  Since we don't explicitly initialize `VTYPE`
on the way to main, if we happen to use a whole register move to place
the pass thru value in the destination register (fairly common), we
may insert the vsetvli *after* the whole register move, and end up with
an exposed whole register move which can fault.  This problem has
been latent the whole time.

Known Hardware
--------------

Old Behavior (No Trap)

* Spacemit-X60 on K1
* C908 on K230
* Likely (but unconfirmed) all other THead processors

New Behavior (Trap)

* Presumably SiFive, but no confirmed specific micro-architectures at this time

Goals
-----

Key Goals:

* Acknowledge the existance and likely long term prevalence of both trapping
  and non-trapping hardware.
* Ensure that there is a correct by construction combination of compiler and
  libraries available for trapping hardware.
* Not fork the ecosystem on this point.  This practically speaking requires
  that any mitigation doesn't impose a noticable performance penalty when
  run on non-trapping hardware.
* Having existing binaries continue to mostly work in practice is highly
  desirable, even they were compiled without knowledge of any changes
  required to address this issue.

Options
-------

Option 1 - Change the ABI
=========================

Since we're in the realm of making backwards incompatible specification
changes anyways, we can change the default calling convention in psABI
in a couple of possible ways:

* Require VTYPE to be non-vill on ABI boundaries.  
* Require VTYPE to be equally vill on ABI boundaries; that is calls
  would have to preserve the single-bit state of whether vill was
  active.
* Require VTYPE to be no more vill on return than on entry to the
  function.  That is, a non-vill VTYPE on entry must be non-vill
  on exit, but a vill VTYPE on entry can become non-vill on exit.
  This would allow callees to unconditionally set VTYPE to any
  non-vill value.  

In all of these variants, VTYPE would remain otherwise unspecified and
unpreserved.  At the moment, variant three seems like the best option.

This would require a kernel change, and we'd end up having to tell folks
that vector code essentially didn't fully work on the unpatched kernel
version.

We'd also have to message and manage an ABI transition.  Older binaries
in the wild would not be guaranteed to work until recompiled.  Note that
this is the same state we're in today, and have been for years, so this
is a bigger problem in theory than in practice.

This is my preferred option, but may be politically unpopular since
it requires publicly admitting the retro-active change was actually
a change.  RVI has generally not wanted to do that in the past.


Option 2 - Enforce the ABI as written
=====================================

This will require the compiler to insert a VSETVLI along any path
from a call boundary to a whole register move.

I can't speak for GCC, but for LLVM this is doable, if exceedingly
ugly.  It will likely result in otherwise spurious vsetvlis, and
its hard to say how much this matters performance wise.

We can do heroics particularly for LTO builds (internal ABIs with
IPO and adapter frames anyone?), but its hard to say if we can
address all performance loss cases which arrise in practice.

As with the previous option, we defacto would have broken packages
in the wild, and nothing would be guaranteed to work until all
packages had been recompiled.  Unlike the previous option, most
of those packages wouldn't "just work" in practice.

Option 3 - Ignore it
====================

This is what we've been doing to date.

Option 4 - Trap and Emulate
===========================

We could have the kernel trap and emulate the instruction.  This
is argubly not crazy for a case where the specification changed.
Since vsetvlis should be fairly common in vector code, this
shouldn't be a hot trap case - unless someone is doing something
weird like hot-looping around a sys-call.

This version basically represents treating the changed behavior
as a SiFive errata.  Note that this will likely always disagree
with the specification document.

Option 4a - Change the Specification
====================================

Several folks have indicates a desire to reverse the change in
the specification.  I am sympathetic to this view, but don't
believe such an effort to be politically viable.

As an alternative, we might be able to propose a specification
change (or maybe an extension?) which allows both the trapping
and non-trapping behaviors.  This wouldn't resove any of the
SW complexity mentioned above, but would at least mean that
the vast majority of vector hardware on the planet wasn't
retroactively considered "non conformant".

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
* Likely (but unconfirmed) all other THead processors

New Behavior (Trap)

* Presumably SiFive, but no confirmed specific micro-architectures at this time

Options
-------

Option 1 - Change the ABI
=========================

Since we're in the realm of making backwards incompatible specification
changes anyways, we can just change psABI to require vtype be non-vill
on ABI boundaries.  It would remain otherwise unspecified and
unpreserved.

This would require a kernel change, and we'd end up having to tell folks
that vector code essentially didn't fully work on the unpatched kernel
version.

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

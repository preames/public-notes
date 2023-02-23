---------------------------
RISCV Specification Minutia
---------------------------

This is a collection of minutia about the change history of the RISCV specifications which have come up on a couple of occassions.  This document is (hopefully!) not relevant for typical users.  

.. contents::

Document Version 2.1 to 2.2
---------------------------

Note: Document versus specification versioning is particular confusing in this case as document 2.1 to 2.2 corresponds to base I specification 2.0 to 2.1.  

Zicsr and Zifenci
=================

Between versions 2.0 and 2.1 of the base I specification, a backwards incompatible change was made to remove selected instructions and CSRs from the base ISA. These instructions were grouped into a set of new extensions, but were no longer required by the base ISA.  

The part of this change relevant for Zicsr and Zifenci is described in “Preface to Document Version 20190608-Base-Ratified” from the specification document.

zicntr
======

Between document version `riscv-spec-v2.1.pdf <https://github.com/riscv/riscv-isa-manual/releases/download/archive/riscv-spec-v2.1.pdf>`_  and document version `riscv-spec-v2.2.pdf <https://github.com/riscv/riscv-isa-manual/releases/download/archive/riscv-spec-v2.2.pdf>`_, the wording which defined the RDCYCLE, RDTIME, and RDINSTRET counters was removed.  At some later point, they were re-added to the specification as Zicntr.  I have not tracked down the change or document version which corresponds to this addition.  It is not document version 2.2.

The ratification status is unclear. Zicntr appears in the `current draft specification <https://github.com/riscv/riscv-isa-manual/releases/tag/draft-20230131-c0b298a>`_ without any indication it might be un-ratified, but late last year we have https://www.reddit.com/r/RISCV/comments/yq73r4/public_review_for_standard_extensions_zicntr_and/. I don't see any formal indication these have been fully ratified.  The best summary of status I can find is `this issue on the profiles repo <https://github.com/riscv/riscv-profiles/issues/43>`_, but even that is not conclusive.

There's an additional problem with the current specification text.  No version number has yet been assigned.  This is tracked as `an open issue against the specification <https://github.com/riscv/riscv-isa-manual/issues/976>`_.

Zihpm
=====

At a high level, Zihpm parallels Zicntr in that ratification status is unclear, and no version has been assigned.  However, hpmcounter3–hpmcounter31 names do not appear to be present in older specification documents.  As such, Zihpm is merely a newly proposed extension as opposed to a backwards incompatible spec change.

Redefinition of PAUSE (Dec 2022)
--------------------------------

In `commit cb3b9d <https://github.com/riscv/riscv-isa-manual/commit/cb3b9d1dcdacefbde6602ada7a0050f5c723ddee>`_ the definition of the PAUSE instruction was changed in a backwards incompatible manner.  Hardware which implemented the old specification does not implement the new one.  This particular change is well justified as the previous definition was ubsurd and useless (it disallowed advancing the program counter), but it wasn't explicitly tracked in any versioning scheme.

Redefinition of Vector Overlap (Nov 2022)
-----------------------------------------

`This proposal <https://lists.riscv.org/g/tech-vector-ext/topic/94729097#845>`_ introduced a wording change which resulted in previously valid encodings become invalid.  This was raised in the discussion, and actively rejected as being a compatibility concern.  This change appears not to have been merged into the `specification repo <https://github.com/riscv/riscv-v-spec/>`_ as of 2023-02-23.  

---------------------------
RISCV Specification Minutia
---------------------------

This is a collection of minutia about the change history of the RISCV specifications which have come up on a couple of occasions.  This document is (hopefully!) not relevant for typical users.  

.. contents::

Document Version 2.1 to 2.2
---------------------------

Between document version `riscv-spec-v2.1.pdf <https://github.com/riscv/riscv-isa-manual/releases/download/archive/riscv-spec-v2.1.pdf>`_  and document version `riscv-spec-v2.2.pdf <https://github.com/riscv/riscv-isa-manual/releases/download/archive/riscv-spec-v2.2.pdf>`_, a backwards incompatible change was made to remove selected instructions and CSRs from the base ISA. These instructions were grouped into a set of new extensions, but were no longer required by the base ISA.  

Note: Document versus specification versioning is particular confusing in this case as document 2.1 to 2.2 corresponds to base I specification 2.0 to 2.1.  

Zicsr and Zifencei
==================

The part of this change relevant for Zicsr and Zifencei is described in “Preface to Document Version 20190608-Base-Ratified” from the specification document.  All of the changes appear to have been at once, and the new extensions were immediately ratified.

zicntr
======

The wording which defined the RDCYCLE, RDTIME, and RDINSTRET counters was removed.  They were re-added to the specification as Zicntr in `commit 77aff0 <https://github.com/riscv/riscv-profiles/commit/77aff0b84edab1fb35dd7080a7371765d28c4da3>`_ in March 2022.

That change includes the following verbage:

"NOTE: Counters and timers (now known as Zicntr and Zihpm) were frozen
but not ratified in 2019, as they were removed from the base ISAs
during the ratification process.  Due to an oversight they were not
later ratified.  As they are required for the RVA20 and RVA22
profiles, the proposal is to ratify these extensions in 2022 and
retroactively add to the 2020 and 2022 profiles as an exception."

The ratification status is unclear. Zicntr appears in the `current draft specification <https://github.com/riscv/riscv-isa-manual/releases/tag/draft-20230131-c0b298a>`_ without any indication it might be un-ratified, but late last year we a `call for public comment <https://www.reddit.com/r/RISCV/comments/yq73r4/public_review_for_standard_extensions_zicntr_and/>_`. I don't see any formal indication these have been fully ratified.  The best summary of status I can find is `this issue on the profiles repo <https://github.com/riscv/riscv-profiles/issues/43>`_, but even that is not conclusive.

There's an additional problem with the current specification text.  No version number has yet been assigned.  This is tracked as `an open issue against the specification <https://github.com/riscv/riscv-isa-manual/issues/976>`_.

Zihpm
=====

At a high level, Zihpm parallels Zicntr in that ratification status is unclear, and no version has been assigned.

However, hpmcounter3–hpmcounter31 names do not appear to be present in older *unprivledged* specification documents.  As such, Zihpm is merely a newly proposed extension as opposed to a backwards incompatible spec change.  Note however that this appears to contradict the text added to the specification document quoted above.  It was pointed out to me that they are mentioned in some of the *privledged* specification documents, but I have not tracked when they were added or tried to reconcile the history of the two specification documents.


Can't we all just hold on a second?
-----------------------------------

For one little instruction, Zihintpause (i.e. the PAUSE instruction) has been a real mess process wise.  This section is largely based on research reported `here <https://inbox.sourceware.org/binutils/f662084e-8b42-a3f4-55b5-8641034d776a@irq.a4lg.com/>`_.

The version number of the `zihintpause` extension **moved backwards** from 2.0 to 1.0 very shortly after being merged into the main repository.  This is easy to write off as a minor issue, except that the `commit which moved the extension number backwards <https://github.com/riscv/riscv-isa-manual/commit/773a6c4cc9db7585d42ec732d5db24f930d1157a>`_ also introduced the sentence "No architectural state is changed.".  If you think about it a bit, this is absolutely absurd because the program counter is part of the architectural state.  This effectively says the instruction must execute forever.  Except, that also contradicts the wording which says the "duration of its effect must be bounded".  So basically, 1.0 is (pedantically) unimplementable.

In Aug 2021, the extension was ratified, and, a few hours later, the version number was increased again to 2.0.  The wording discussed above remained.

In `commit cb3b9d <https://github.com/riscv/riscv-isa-manual/commit/cb3b9d1dcdacefbde6602ada7a0050f5c723ddee>`_ (Dec 2022) the definition of the PAUSE instruction was again revised to remove the "No architectural state is changed." wording.  This is great, and long overdue.  However, the version number of the extension was *not* increased.  So as a result, we have two versions of the extension text - both which claim to be 2.0 - which are mutually incompatible.  Arguably, this was a small enough matter that an errata should suffice, but well, we don't have one of those either.

As a practical matter, the consensus seems to be to basically ignore the matter.  The prior text was unimplementable, and if you ignore that sentence, all of the known versions are substantially similar.  As a result, the discrepancies in version can mostly be ignored, and we pretend that only the most recent 2.0 version ever existed.

Zmmul vs M
----------

Discussion in the issue `Is Zmmul a subset of M? <https://github.com/riscv/riscv-isa-manual/issues/869>`_ appears to indicate that in a pendantic sense that `Zmmul` is not a strict subset of `M`.  Specifically, `M` allows some configurations which don't actually support multiplication at runtime, whereas `Zmmul` does not.  Given toolchains completely ignore this possibility to start with - seriously, don't tell your toolchain you have a multiply instruction if it's disabled at runtime - in all practical sense `Zmmul` does appear to be a subset of `M`.  

Redefinition of Vector Overlap (Nov 2022)
-----------------------------------------

`This proposal <https://lists.riscv.org/g/tech-vector-ext/topic/94729097#845>`_ introduced a wording change which resulted in previously valid encodings become invalid.  This was raised in the discussion, and actively rejected as being a compatibility concern.  This change appears not to have been merged into the `specification repo <https://github.com/riscv/riscv-v-spec/>`_ as of 2023-02-23.  

Whole Vector Register Move and VILL
-----------------------------------

The 1.0 version of the vector specification says the following in section 3.4.4. "Vector Type Illegal vill":

   "If the vill bit is set, then any attempt to execute a vector instruction that depends upon vtype will raise an illegal-instruction exception.  Note vset{i}vl{i} and whole-register loads, stores, *and moves* do not depend upon vtype."

By version 20240411 of the combined unpriv specification, this wording has been changed to:

   "If the vill bit is set, then any attempt to execute a vector instruction that depends upon vtype will raise an illegal-instruction exception. vset{i}vl{i} and whole register loads and stores do not depend upon vtype."

Note that whole register moves have been *removed* from this note, and thus
are now required to raise an illegal-instruction exception on vill.

Both versions have the following note in section 31.16.6 "Whole Vector Register Move":

   "These instructions are intended to aid compilers to shuffle vector registers without needing to know or change vl or vtype."

Given ``vill`` is a bit within the ``vtype`` CSR ("The vill bit is held in bit XLEN-1 of the CSR to support checking for illegal values with a branch on the sign bit."), this really seems like the new version of the specification contradicts itself.

This change was introduced by:

   commit 856fe5bd1cb135c39258e6ca941bf234ae63e1b1
   Author: Andrew Waterman <andrew@sifive.com>
   Date:   Mon Apr 3 15:40:16 2023 -0700

    Delete non-normative claim that vmv<nr>r.v doesn't depend on vtype

    The normative text says that vmv<nr>r.v "operates as though EEW=SEW",
    meaning that it _does_ depend on vtype.

    The semantic difference becomes visible through vstart, since vstart is
    measured in elements; hence, how to set vstart on an interrupt, or
    interpret vstart upon resumption, depends on vtype.

Personally, I think this was the wrong change to resolve the stated issue.
The wording changed was in a section specific to vill exception behavior,
and adding a carve out that whole vector register move explicitly
did not trap on vill (but otherwise did depend on vtype) would have been
much more reasonable.

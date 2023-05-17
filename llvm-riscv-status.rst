-------------------------------------------------
Overall status of RISCV in LLVM
-------------------------------------------------

This document contains an initial survey of gaps in the RISCV LLVM toolchain ecosystem.  It is being written in May 2022 as I come up to speed on RISCV, and start to wrap my head around the shape of things in general.  It may or may not stay current, so if you're reading this long after the date it was written, keep in mind it may be out of date.  All of the analogous docs I could find online certaintly were!

.. contents::

Functional
----------

Draft Extensions
================

There are numerous potential extensions in flight.  The following is a list of specification links for a few of the potentially interesting ones.  This explicitly excludes anything `already implemented in LLVM <https://llvm.org/docs/RISCVUsage.html>`_.

* `Zc* variants <https://github.com/riscv/riscv-code-size-reduction/releases>`_
* `Vector crypto extensions <https://github.com/riscv/riscv-crypto/releases>`_, https://reviews.llvm.org/D138807
* `bfloat16 support <https://github.com/riscv/riscv-bfloat16/releases>`_
* CFI

Rash of Linker issues
=====================

As of May 2023, I'm aware of an odd rash of confirmed or suspected linker errors.  Listing these all out to simplify tracking:

* [Landed] https://github.com/llvm/llvm-project/issues/62535 -- The fix for this still looks pretty suspect for this.
* [Landed] https://reviews.llvm.org/D150722 "ld.lld: error: section size decrease is too large" 
* [Open] https://reviews.llvm.org/D149432 -- Region sizes are computed before relaxation is done in LLD.
* [Landed[ Repeat relaxation of symbol aliases in LLD.  Patch posted as https://reviews.llvm.org/D150220, but discussion revealed already fixed (by accident) in https://reviews.llvm.org/D149735.  
* [Undiagnosed] Failure in LTO spec builds, not yet triaged to upstream issue.  Believe to not overlap with preceeding.


GNU vs LLVM Toolchain Compatibility
===================================

I have been told that mixing object files from g++ and clang does not work reliably.  I've also been told that linking gnu generated object files with LLVM's LD does not work reliably.  Essentially, we have likely differences in ABI interpretation.

Here are some example issues in the recent past:

* https://github.com/llvm/llvm-project/issues/57084 was caused by incorrect argument handling for struct arguments.  It has been fixed.

Here are specific open items I'm aware of:

* https://github.com/llvm/llvm-project/issues/57261 is an open issue around argument passing of values less than ELEN.  It's open currently, but likely to be fixed shortly.
* I have been told that llvm-objdump is reporting zero sizes and failing to disassemble certain gcc compiled object files.  No details available at this time, and issue has not been confirmed with a test case. This may be related to the suspected ELF interpretation differences below.
* In the process of reviewing the psABI document which is currently going through ratification, I stumbled across `one real difference <https://github.com/riscv-non-isa/riscv-elf-psabi-doc/issues/197>`_.  In this case, GNU assumes a pc-relative relocation can always resolve to zero even if that's out of bounds for the pc-relative range.  LLVM LLD considers this an error, and asserts that a PLT/GOT entry should have been used instead.  This means that LLD can not be used to link gcc generated object files in this case.

Beyond these specific issues, there are likely others.  We need to invest time in systematically testing for further issues.  We may want to take a look at the effort which was done a few years ago for the microsoft ABI; we may be able to leverage some of the tooling.


Frame setup problems
====================

I've been told from a couple sources that frame setup is not correct.  We know have at least two confirmed issues, but where there are two, there are probably more.  Known issues:

* Its been mentioned to me that scalable allocas may not be lowered correctly.  Possibly in combination with frame alignment interactions.
* Fraser fixed a couple of misaligned RVV stack problems recently. 
* Kito has a separate issue around exception handling.  `Tracked in 55442 <https://github.com/llvm/llvm-project/issues/55442>`_ 

LLDB Support
============

In tree, LLDB apparently does not fully work on RISCV.  Exact status unclear.  I've heard reports that with out of tree changes, using it for remote debugging does work, but I don't know where these changes are or progress on getting them upstream.

Workaround: GDB appears to work well with LLVM generated code, and is widely used for this purpose.

Debug info quality in the backend is unclear.  Would be good to do a systematic search for issues ala the Sony efforts from a few years ago.

Split Dwarf Issue
+++++++++++++++++

I have been told that there is an issue with split dwarf.  If I understood correctly, the actual issue is target independent, but RISCV will see it at higher frequency.

My understanding is that split dwarf doesn't allow relocations which change function sizes in the split portion.  Specifically, applying fixups in the split files is undesirable to reduce link time.  Because of the strategy taken with call relaxation, RISC-V is much more likely to see this problem in practice than other targets.

Workaround: Don't use split dwarf.  Or disable -mrelax.

Sanitizer Support for Scalable Vectors
======================================

https://github.com/llvm/llvm-project/issues/61096 reveals that the sanitizers were never updated to account for scalable vector types.  Since I enabled auto-vectorization with scalable vectors by default last summer, this means that various sanitizers may crash when used in combination with the V extension.  I did an audit of some of the near by code, and identified a bunch of issues which need fixed.

ASAN
   Initial patches landed, thought to work.  No end-to-end testing as of yet.

MSAN
   Initial change landed, can instrument simple load/stores.  Argument handling not yet implemented.

TSAN
   Preventing a crash will be easy, but proper support may require a new runtime routine.

HWASAN
   Initial change landed, can instrument simple load/stores.  Stack (scalable alloca) not yet implemented.

BoundsChecking
   Changes landed, should work, no end-to-end testing as of yet.

SanitizerCoverage
   Easy to disable.

**WORKAROUND:** Use `-fno-vectorize` or do not add `V` extensions to architectural string when using sanitizers.


VLEN=32 is known to be broken
=============================

This means that Zve32x and Zve32f are not supported.  Specific problems noted were around vscale computation and "scalable types" (unclear exact meaning to me).

It is not clear to me that anyone is ever going to care about this.  I'm not aware of any hardware existing or announced which would need this.

Testing Infrastructure
----------------------

No public RISCV llvm build bot
==============================

The RISCV target is built by default, and thus LIT tests do run widely.  The part that’s missing is the execution testing on an actual RISCV environment.  This gap means we’re more likely to miss linkage and dynamic loading issues, or generally any issues which requires interaction between multiple components of the toolchain.

ISEL Fuzzing Disabled
=====================

OSS Fuzz used to do fuzzing of various LLVM backends.  This helps to find recent regressions by finding examples which trigger crashes and assertion failures in newly introduced code.  However, due to a build configuration problem, this was recently disabled.  We need to renable this in general, but also add RISCV to the list of fuzzed targets.  

See `discussion here <https://github.com/google/oss-fuzz/pull/7179#issuecomment-1092802635>`_ and linked pull requests on the OSS Fuzz repo.


Performance
-----------

LLD - Linker Optimization and Relaxation
========================================

Up until recently, LLD did not implement either linker optimization (substituting one code sequence for a smaller/faster one when resolving relocations) or relaxation (shrinking code size exploiting smaller sequences found via optimization.)  However, the infrastructure to do so is now in tree, and `D127611 <https://reviews.llvm.org/D127611>`_ included support for call relaxation for both PC relative and absolute addresses.  This covered cases where target address was initially a 32 bit immediate or 32 bit relative.

Cases known to be missing today:

* Branch relaxation with 32 bit immediate or PC relative.
* GP relative addressing.  (Unclear status?)
* Relaxation of 64 bit immediate or 64 bit relative offset cases.  Likely requires specification of Large code model.

Loop Vectorization
==================

ARM SVE has pioneered support in the loop vectorizer for runtime vector lengths in the main loop, while using a scalar epilogue loop to handle the last couple of iterations.  I have been actively working towards enabling loop vectorization for RISC-V.  Today, upstream LLVM will auto-vectorize with both scalable and fixed length vector types, picking whichever is cheapest.

In practice, scalable vectors are almost always scalable unless there's a gap in what we can vectorize.  The major gap left is handling of interleave groups (a.k.a. segmented load/stores on RISCV).  This gap is under active development (see https://reviews.llvm.org/D144092 and related reviews).  All other interesting functional gaps are, to my knowledge, fixed.  If you encounter other gaps, please report them.

In terms of performaning tuning, we're still in the early days.  I've been fixing issues as I find them, but there's a couple of larger gaps known such as LMUL>1 enablement.  Concrete bug reports for vector code quality are very welcome.


SLP Vectorization
+++++++++++++++++

I've run reasonable broad functional testing without issue.  However, SLP is still disabled by default due to code quality problems which have not yet been adddressed.

The major issues for SLP/RISCV I currently know of are:

* We have a cost modeling problem for vector constants. SLP mostly ignores the cost of materializing constants, and on most targets that works out mostly okay. RISCV has unusually expensive constant materialization for large constants, so we end up with common patterns (e.g. initializing adjacent unsigned fields with constants) being unprofitably vectorized. Work on this started under D126885, and there is ongoing discussion on follow ups there.
* We will vectorize sub-word parallel operations and don't have robust lowering support to re-scalarize. Consider a pair of i32 stores which could be vectorized as <2 x i32> or could be done as a single i64 store. The later is likely more profitable, but not what we currently generate. I have not fully dug into why yet.

Note that both of these issues could exist for LV in theory, but are significantly less likely. LV is strongly biased towards constant splats and longer vectors. Splats are significantly cheaper to lower (as a class), and longer vectors allows fixed cost errors to be amortized across more elements.

Another concern is that SLP doesn't always respect target register width and assumes legalization.  I somewhat worry about how this will interact with LMUL8 and register allocation, but I think I've convinced myself that the same basic problem exists on all architectures.  (For reference, SLP will happily generate a 128 element wide reduction with 64 bit elements.  On a 128 bit vector machine, that requires stack spills during legalization.)  Such sequences don't seem to happen in practice, except maybe in machine generated code or cases where we've over-unrolled.  



Performance (Minor)
-------------------

Things in this category are thought to be worth implementing individually, but likely individually minor in their performance impact.  Eventually, everything here should be filed as a LLVM issue, but these are my rough notes for the moment.  

Frame lowering optimization
===========================

I have been working on a series of small patches (https://reviews.llvm.org/D139037, https://reviews.llvm.org/D132839, and related NFCs) to improve the instruction sequences used for accessing spill slots on the stack.  Initial focus has been on frames greater than 2k.

This started with a previous set of fixes (https://reviews.llvm.org/D137593, https://reviews.llvm.org/D137591) to avoid use of vlenb when the exact VLEN is known. When we compile vector code with an exactly known VLEN, larger frames become relatively common.  

Anoyingly, the largest immediate we can fold into a load or store is 2k, and we can’t fold any immediate into a vector load/store.  As a result, I started looking into improvements for fixed offset addressing sequences in frames just larger than 2k.  This has hit a logical stopping point, so I’m likely to shift focus until I hit another example which justifies further time spent here.

There are two open items:

* We should be able to reuse the vlenb value instead of reloading it each time.
* We end up materialing the high part of the frame offset (which is shared across most frame accesses) many times.  This is down to a single LUI now, but we should still not need to materialize it repeatedly.

For the moment, I'm monitoring https://reviews.llvm.org/D109405.  Once that's in, it may provide a framework for solving both of the previous items.  The general problem we have here is that frame lowering happens after register allocation, so things such as these become much more chalenging.  


Global Merge
============

The following is basically a brain dump on a few things vaguely related to GlobalMerge for RISCV.  This isn't a review comment on this review per se.  Some of this came from discussion w/Palmer because I nerd sniped myself into thinking this a bit too hard, and he was willing to brainstorm with me.  I then did the same to @craig.topper a bit later, and edited in some further changes.

Profitability wise, we have three known cases.

Case 1 is where the alignment guarantees the second address could fold into the consuming load/store instruction.   The simplest case would be to restrict to when at least one of the globals being merged had a sufficiently large alignment.  https://reviews.llvm.org/D129686#inline-1380320 has some brainstorming on a more advanced boundary align mechanism, but building that out is likely non trivial.  There have been some other use cases for analogous features in the past, but I don't have details.

Case 2 is when we have three or more accesses using the same global (regardless of alignment).  In this case, we only need one lui/addi pair + one access with small folded offset for each of the original access.  This is a 1 instruction savings for each additional access.

Case 3 is a size optimization only.  This is Alex's https://reviews.llvm.org/D129686 and is geared at using compressed instructions to share common addresses.

For the GP interaction, we may want to take a close look at how gcc models global merging vs how we do.  Per Palmer, it keeps around the symbols for each global, and that may impact the heuristic that LD uses for selecting globals to place near GP.  We may be able to massage our output a bit to line up with the existing heuristics.  

There's a question of how worthwhile this is.   For anything beyond static builds with medlow, we need to worry about pc relative addresses.  Out of the three known profitable cases above, case 2 and 3 apply to pc relative sequences without knowing the alignment of the auipc, but case 1 does not.  For case 1, we'd need to additionally account for the alignment of the auipc.  We could potentially insert an align directive, but that wastes space.  Per Palmer, there was some previous discussion around a relocation type for an optimized "aligned auipc" construct which used (at most) a single extra instruction.  However, no one has pushed this forward.

My current thinking is that we should probably enable this for code size minimization only, and return to it at a later point.  


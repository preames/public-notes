-------------------------------------------------
Overall status of RISCV in LLVM
-------------------------------------------------

This document contains a survey of major gaps in the RISCV LLVM toolchain ecoystem.  It was initially written in May 2022 as I first came up to speed on RISCV.  It was most recently majorly updated in July 2023.  It may or may not stay current, so if you're reading this long after the date it was written, keep in mind it may be out of date. 

.. contents::

Functional
----------

At a macro level, we appear to be convergening towards a feature complete toolchain for common use cases.  There are still a few gaps, but many of the major issues identified in the initial survey are now mostly complete.

Support for Draft Extensions
============================

There are numerous potential extensions in flight.  The following is a list of specification links for a few of the potentially interesting ones.  This explicitly excludes anything `already implemented in LLVM <https://llvm.org/docs/RISCVUsage.html>`_.

* `zacas <https://github.com/riscv/riscv-zacas/>`_, https://reviews.llvm.org/D149248
* Zicclsm
* Zam

ABI Questions
=============

There are a couple areas where we need clarification and extensions to the psABI. On the smaller side, there are some `minor changes required for bf16 <https://github.com/riscv-non-isa/riscv-elf-psabi-doc/pull/367>`_.  On the more major side, we do not have a ratiied vector ABI.  Eventually, we will need support for a large code model variant.  We should probably also get the TLSDESC bits finalized and in.

Intrinsics
==========

TBD - Major distinction between vector intrinsics and all others.

Function Multi Versioning
=========================

Classic multi versioning via distinct compiler command lines and linking appears to work as expected.  LTO appears to have some suprising (but correct) interactions, see the section below.  (Warning: Use C, not C++!  C++ has different manging and dispatch rules.).

Use of a custom resolver routine (via ``__attribute__((ifunc("resolver")))``) appears to work as expected.  This can be combined with the prior mechanism to support lazily bound dispatch via user-defined mechanisms.  Note that if the target function uses the (highly experimental) vector ABI, we loose lazy binding and instead have all the resolutions done eagerly.

Use of the target attribute (``__attribute__ ((target ("arch=+v")))``) is unsupported.  This appears to be a target specific syntax, and hasn't been implemented for RISCV as of yet.  See https://reviews.llvm.org/D151730.

Use of the default ifunc resolver (which is invokved via either compiler machinery for target attribute manging for C++ source or via target_clones) requires the availablity of hwprobe (or hwcaps for limited feature set).  My understanding is that the kernel patches recently landed, and that the glibc usage is pending. I am unclear whether the default resolver is emitted by the compiler, or provided by glibc.

Use of the target_clones attribute (``__attribute__((target_clones("default","arch=+v","arch=-v")))``) is unsupported.  This depends on both of the previously mentioned items.

Summary of open tasks:

* Implement target attribute.
* Ensure hwprobe mechanism works for manual resolver.
* Watch hwprobe progress in glibc.
* Implement target_clones attribute.
* Explore vector calling convention interaction and ways to preserve lazy binding.

LTO
===

I keep hearing about problems with LTO, but have few specific details.  The only concrete items I currently know of are non-functional user interface issues, but I suspect the existance of functional problems as well.

Known issues:

* When linking multiple translation units compiled with distinct target features (i.e. ``-march=rv64gcv`` vs ``-march=rv64g``), LTO produces a different arch attribute in the final ELF than a normal link does.  LTO appears to take the intersection, whereas normal linking appears to take union.  The result of this is that llvm-objdump and friends fail to disassemble some code in LTO linked binaries.

Suspected Issues:

* After a fairly minor amount of trying, I was unable to get LTO working via the ld.gold plugin mechanism.  I found some online discussion indicating that architectural support in gold might be required, but have not pursued this further.  This may be user error.
* We previously had issues with assembly excessively sized functions, or linking (in LLD) with execively sized sections.  Neither of these were technically LTO specific, but LTO is significantly more likely to produce large link inputs.   There may be more such cases lurking.  https://reviews.llvm.org/D154958 may be one such example.
* There's some old patches talking about problems mixing ABIs in the same LTO step.  I haven't investigated this at all.


CFI/Shadow Stack
================

There are two major threads of work on this. Pure software Forward CFI and Shadow Stack appears to be complete.  Recent changes have landed to support KCFI, and shadow stack via software emulation, and the android folks have reported no remaining blocking items.

Hardware assisted CFI/SS is blocked on the stablization of the `relevant extensions <https://github.com/riscv/riscv-cfi/>`_.  Recently (as of July 2023), several rounds of sigificant feeback from ARC have made it seem that progress towards that goal is unlikely in the immediate future.  There's a bunch of toolchain work blocked behind having a reasonable stable specification.

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

Sanitizer Support
=================

My current understanding is that all of the sanitizers work with sv39 and rv64gc.

Interactions with Scalable Vectors
++++++++++++++++++++++++++++++++++

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

UBSAN
   Not yet investigated.

**WORKAROUND:** Use `-fno-vectorize` or do not add `V` extensions to architectural string when using sanitizers.

Non-sv39 systems
++++++++++++++++

I have honestly not been following this line of work, but there's clearly some set of remaining issues with enabling santizers on sv48 and sv57.  A couple of starting point patches for investigation:

* https://reviews.llvm.org/D139823
* https://reviews.llvm.org/D139827
* https://reviews.llvm.org/D152895
* https://reviews.llvm.org/D152990
* https://reviews.llvm.org/D152991

**WORKAROUND:** Use sv39.

VLEN=32 is known to be broken (WONTFIX)
=======================================

This means that Zve32x and Zve32f are not supported.  It is not clear to me that anyone is ever going to care about this.  I'm not aware of any hardware existing or announced which would need this.

Stablity
--------

These items were previously under functional, but were moved to reflect the fact they're basically bugs, and from the lack of progress or reported concern on several, not highly impactful bugs at that.

My overall impression at this point is that we're in a reasonable stable state, but are lacking serious burn in.  A couple of vendors have shipped LLVM based toolchains, but it's unclear how hard these have actually been hammered at scale.  We also know that said vendors are shipping branches with some fairly major feature divergences from upstream, so it may be they're shipping non-trivial amounts of bug fixes as well.

In terms of open source, Android (and particularly ClangBuiltLinux) are our largest public users following upstream closely.  We're leaning fairly heavily on them noticing issues.

Open Linker issues
==================

* [Open] https://reviews.llvm.org/D149432 -- Region sizes are computed before relaxation is done in LLD.


GNU vs LLVM Toolchain Compatibility
===================================

A couple months back, I was told by multiple parties that mixing object files from g++ and clang did not work reliably.  I've also been told that linking gnu generated object files with LLVM's LD does not work reliably.  We'd had a couple of specific issues which we identified and fixed.  I have not heard specific failure reports after that, but we may have other issues yet to be found.

We need to invest time in systematically testing for further issues.  We may want to take a look at the effort which was done a few years ago for the microsoft ABI; we may be able to leverage some of the tooling.


Frame setup problems
====================

I've been told from a couple sources that frame setup is not correct.  We know have at least two confirmed issues, but where there are two, there are probably more.  Known issues:

* Its been mentioned to me that scalable allocas may not be lowered correctly.  Possibly in combination with frame alignment interactions.
* Fraser fixed a couple of misaligned RVV stack problems recently. 
* Kito has a separate issue around exception handling.  `Tracked in 55442 <https://github.com/llvm/llvm-project/issues/55442>`_ 

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


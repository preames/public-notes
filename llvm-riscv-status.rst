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

Moving to latest specification
==============================

Punch list:

* F implies Zicsr (Finx probably does too)
* Zihpm, and Zicntr
* Various version number updates - thought to be non-semantic, but check!
* Double check CPU definitions - need to add zicsr, zifencei, zihpm, zicntr as appropriate
* Meaning of G, and canonical march string

Rash of Linker issues
=====================

As of May 2023, I'm aware of an odd rash of confirmed or suspected linker errors.  Listing these all out to simplify tracking:

* https://github.com/llvm/llvm-project/issues/62535 -- Appears to result in incorrect debug information.
* "ld.lld: error: section size decrease is too large" -- Believed to be an overflow on the delta after applying relaxations.  No patch or reproducer upstream yet.
* https://reviews.llvm.org/D149432 -- Region sizes are computed before relaxation is done in LLD.
* Repeat relaxation of symbol aliases in LLD.  Patch exists, but hasn't made it upstream yet.  
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


Concerning items in LLVM issue tracker
======================================

Skiming through the issue tracker for "riscv", I see a couple of concerning looking items.

*  [SelectionDAGISel] Mysteriously dropped chain on strict FP node. `#54617 <https://github.com/llvm/llvm-project/issues/54617>`_.  This appears to be a wrong code bug for strictfp which affects RISCV.
*  [RISCV] wrong vector register alloc in vector instruction `#50157 <https://github.com/llvm/llvm-project/issues/50157>`_.  Appears to be a miscompile of vgather intrinsic, and may hint at a larger lurking issue.

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

Vectorization
=============

ARM SVE has pioneered support in the loop vectorizer for runtime vector lengths in the main loop, while using a scalar epilogue loop to handle the last couple of iterations.  I have been actively working towards enabling loop vectorization for RISC-V.  Today, upstream LLVM will auto-vectorize with both scalable and fixed length vector types, picking whichever is cheapest.

In practice, scalable vectors are almost always scalable unless there's a gap in what we can vectorize.  The major gap left is handling of interleave groups (a.k.a. segmented load/stores on RISCV).  This gap is under active development (see https://reviews.llvm.org/D144092 and related reviews).  All other interesting functional gaps are, to my knowledge, fixed.  If you encounter other gaps, please report them.

In terms of performaning tuning, we're still in the early days.  I've been fixing issues as I find them, but there's a couple of larger gaps known such as LMUL>1 enablement.  Concrete bug reports for vector code quality are very welcome.

Tail Folding
++++++++++++

For code size reasons, it is desirable to be able to fold the remainder loop into the main loop body.  At the moment, we have two options for tail folding: mask predication and VL predication.  I've been starting to look at the tradeoffs here, but this section is still highly preliminary and subject to change.

Mask predication appears to work today.  We'd need to enable the flag, but at least some loops would start folding immediately.  There are some major profitability questions around doing so, particularly for short running loops which today would bypass the vector body entirely.

Talking with various hardware players, there appears to be a somewhat significant cost to using mask predication over VL predication.  For several teams I've talked to, SETVLI runs in the scalar domain whereas mask generation via vector compares run in the vector domain.  Particular for small loops which might be vector bottlenecked, this means VL predication is preferrable.

For VL predication, we have two major options.  We can either pattern match mask predication into VL predication in the backend, or we can upstream the work BSC has done on vectorizing using the VP intrinsics.  I'm unclear on which approach is likely to work out best long term.

Work on tail folding is currently being deferred until main loop vectorization is mature.

SLP Vectorization
+++++++++++++++++

I've run reasonable broad functional testing without issue.  However, SLP is still disabled by default due to code quality problems which have not yet been adddressed.

The major issues for SLP/RISCV I currently know of are:

* We have a cost modeling problem for vector constants. SLP mostly ignores the cost of materializing constants, and on most targets that works out mostly okay. RISCV has unusually expensive constant materialization for large constants, so we end up with common patterns (e.g. initializing adjacent unsigned fields with constants) being unprofitably vectorized. Work on this started under D126885, and there is ongoing discussion on follow ups there.
* We will vectorize sub-word parallel operations and don't have robust lowering support to re-scalarize. Consider a pair of i32 stores which could be vectorized as <2 x i32> or could be done as a single i64 store. The later is likely more profitable, but not what we currently generate. I have not fully dug into why yet.

Note that both of these issues could exist for LV in theory, but are significantly less likely. LV is strongly biased towards constant splats and longer vectors. Splats are significantly cheaper to lower (as a class), and longer vectors allows fixed cost errors to be amortized across more elements.

Another concern is that SLP doesn't always respect target register width and assumes legalization.  I somewhat worry about how this will interact with LMUL8 and register allocation, but I think I've convinced myself that the same basic problem exists on all architectures.  (For reference, SLP will happily generate a 128 element wide reduction with 64 bit elements.  On a 128 bit vector machine, that requires stack spills during legalization.)  Such sequences don't seem to happen in practice, except maybe in machine generated code or cases where we've over-unrolled.  


Code Size
=========

There has been a general view that RISCV code size has significant room for improvement aired in recent LLVM RISC-V sync-up calls, but no specifics are currently known.

2022-07-11 - I spent some time last week glancing at usage of compressed instructions.  Main take away is that lack of linker optimization/relaxation support in LLD was really painful code size wise.  We should revisit once that support is complete, or evaluate using LD in the meantime.


Performance (Minor)
-------------------

Things in this category are thought to be worth implementing individually, but likely individually minor in their performance impact.  Eventually, everything here should be filed as a LLVM issue, but these are my rough notes for the moment.  

Interesting cases from the LLVM issue tracker:

*  Unaligned read followed by bswap generates suboptimal code `#48314 <https://github.com/llvm/llvm-project/issues/48314>`_
   

LoopVectorizer generating duplicate broadcast shuffles
======================================================

This is being fixed by the backend, but we should probably tweak LV to avoid anyways.

Duplicate IV for index vector
=============================

In a test which simply writes “i” to every element of a vector, we’re currently generating:

 %vec.ind = phi <4 x i32> [ <i32 0, i32 1, i32 2, i32 3>, %vector.ph ], [ %vec.ind.next, %vector.body ]
  %step.add = add <4 x i32> %vec.ind, <i32 4, i32 4, i32 4, i32 4>
  …
  %vec.ind.next = add <4 x i32> %vec.ind, <i32 8, i32 8, i32 8, i32 8>
  %2 = icmp eq i64 %index.next, %n.vec
  br i1 %2, label %middle.block, label %vector.body, !llvm.loop !8

And assembly:

    vadd.vi    v9, v8, 4
    addi    a5, a3, -16
    vse32.v    v8, (a5)
    vse32.v    v9, (a3)
    vadd.vi    v8, v8, 8
    addi    a4, a4, -8
    addi    a3, a3, 32
    bnez    a4, .LBB0_4
    beq    a1, a2, .LBB0_8

We can do better here by exploiting the implicit broadcast of scalar arguments.  If we put the constant id vector into a vector register, and add the broadcasted scalar index we get the same result vector.

Branch on inequality involving power of 2
=========================================

For the compare:
  %c = icmp ult i64 %a, 8
  br i1 %c, label %taken, label %untaken

We currently emit:
    li    a1, 7
    bltu    a1, a0, .LBB0_2

We could emit:
    slli    a0, a0, 3
    bnez    a0, .LBB1_2

This lengthens the critical path by one, but reduces register pressure.  This is probably worthwhile.

There are also many variations of this type of pattern if we decide this is worth spending time on.  
   
Optimizations for constant physregs (VLENB, X0)
===============================================

Noticed while investigating use of the PseodoReadVLENB intrinsic, and working on them as follow ons to `<https://reviews.llvm.org/D125552>`_, but these also apply to other constant registers.  At the moment, the two I can think of are X0, and VLENB but there might be others.

Punch list (most have tests in test/CodeGen/RISCV/vlenb.ll but not all):

* PeepholeOptimizer should eliminate redundant copies from constant physregs. (`<https://reviews.llvm.org/D125564`_)
* PeepholeOptimizer should eliminate redundant copies from unmodified physregs.  Looking at the code structure, we appear to already do all the required def tracking for NA copies, and just need to merge some code paths and add some tests.
* SelectionDAG does not appear to be CSEing READ_REGISTER from constant physreg.
* MachineLICM can hoist a COPY from constant physreg since there are no possible clobbers.
* forward copy propagation can forward constant physreg sources.
* Remat (during RegAllocGreedy) can trivially remat COPY from constant physreg.

X0 specific punch list:

* Regalloc should prefer constant physreg for unused defs.  (e.g. generalize 042a7a5f for e.g. volatile loads)  May be able to delete custom AArch64 handling too.

VLEN specific punch list:

* VLENB has a restricted range of possible values, port pseudo handling to generic property of physreg.
* Once all above done, remove PseudoReadVLENB.


Vaguely related follow on ideas:

* A VSETVLI a0, x0 <vtype> whose implicit VL and VTYPE defines are dead essentially just computes a fixed function of VLENB.  We could consider replacing the VSETVLI with a CSR read and a shift.  (Unclear whether this is profitable on real hardware.)


Optimizations for VSETVLI insertion
===================================

This is collection of pending items for improving VSETVLI placement.  In general, I think we're starting to hit the point of diminishing returns here, and some of the items noted below stand a good chance of being punted to later.

Optimization

* https://github.com/llvm/llvm-project/issues/55615 -- not really VSETVLI specific, looks like a bad interaction with fixed width vs scalable lowering
* We seem to end up with vsetvli which only toggle policy bits (tail and mask agnosticism).  There look to be oppurtunities here, but my first approach didn't work (https://reviews.llvm.org/D126967).  Pending discussion on approach.
* Missing DAGCombine rules:

  * Canonicalize AVLImm >= VLMax to VLMax register form.
  * GPR = vsetvli <value>, GPR folds to value when <value> less than VLMAX
  * If AVL=VLMAX, then TU is meaningless and can become TA.
  * If unmasked, then MU is meaningless and can become TU.

Vectorization
=============


* Issues around epilogue vectorization w/VF > 16 (for fixed length vectors, i8 for VLEN >= 128, i16 for VLEN >= 256, etc..)
* Initial target assumes scalar epilogue loop, return to folding/epilogue vectorization in future.


Compressed Expansion for Alignment
==================================

If we have sequence of compressed instructions followed by an align directive, it would be better to uncompress the prior instructions instead of asserting nops for alignment.

This is analogous to the relaxation support on X86 for using larger instruction encodings for alignment in the integrated assembler.

This is of questionable value, but might be interesting around e.g. loop alignment.

Scalable Vectorizer Gaps
========================

Here is a punch list of known missing cases around scalable vectorization in the LoopVectorizer.  These are mostly target independent.

* Interleaving Groups.  This one looks tricky as selects in IR require constants and the required shuffles for scalable can't currently be expressed as constants.  This is likely going to need an IR change; details as yet unsettled.  Current thinking has shifted towards just adding three more intrinsics and deferring shuffle definition change to some future point.  Pending sync with ARM SVE folks.
* General loop scalarization.  For scalable vectors, we _can_ scalarize, but not via unrolling.  Instead, we must generate a loop.  This can be done in the vectorizer itself (since its a generic IR transform pass), but is not possible in SelectionDAG (which is not allowed to modify the CFG).  Interacts both with div/rem and intrinsic costing.  Initial patch for non-predicated scalarization up as `D131118 <https://reviews.llvm.org/D131118>`_
* Unsupported reduction operators.  For reduction operations without instructions, we can handle via the simple scalar reduction loop.  This allows e.g. a product reduction to be done via widening strategy, then outside the loop reduced into the final result.  Only useful for outloop reduction.  (i.e. both options should be considered by the cost model)

RISCV Target Specific:

* vectorizable intrinsic costs.  We are missing a bunch of intrinsic costs for vectorized intrinsic calls.  This results - due to the inability to scalarize - in invalid costs being returned and thus vectorization not triggering.  I've added floating point rounding and integer intrinsics, but we need to cost the remainder.

Tail Folding Gaps
=================

Tail folding appears to have a number of limitations which can be removed.

* Some cases with predicate-dont-vectorize are vectorizing without predication.  Bug.
* Any use outside of loop appears to kills predication.  Oddly, on examples I've tried, simply removing the bailout seems to generate correct code?
* Stores appear to be tripping scalarization cost not masking cost which inhibits profitability.
* Uniform Store.  Basic issue is we need to implement last active lane extraction.  Note active bits are a prefix and thus popcnt can be used to find index.  No current plans to support general predication.

Constant Materialization Gaps
=============================

For constant floats, we have a couple oppurtunities:

* LUI/SHL-by-32/FMV.D.X - Analogous to the LUI/FMV.W.X pattern recently implemented, but requires an extra shift.  This basically reduces to increasing the cost threshold by 1, and may be worth doing for doubles.  
* LI/FCVT.S.W - Create a small integer, and convert to half/single/double.  Note this is a convert, not a move.  For half, LUI/FMV.H.X may be preferrable.
* FLI.S/D - Likely to be optimal when Zfa is available.
* FLI + FNEG.S - Can be used to produce some negative floats and doubles.  LUI/FMV.W.X is likely better for floats and halfs, so this mostly applies to doubles.  FNEG.S can be used to toggle the sign bit on any float, so may be more broadly applicable as well.


Current constant materialization for large constant vectors leaves a bit to be desired.  Here's a list of cases which might be interesting to improve:

* Forming vector splats for constant fixed length vectors which can't be folded into operand (e.g. for a store).  Currently, we emit constant pool loads where-as splatting an etype constant would be significantly better.  Shows up in idiomatic vectorized constant memset patterns.
* Forming vector splats where the element size is larger than the largest natively supported element.  (e.g. splat of a 128b value with largest etype being e64.)  Shows up in vector crypto, and probably any i128 math lib.  One strategy is to splat two vectors (one for high, one for low), and then mask them together.  Can probably generalize for a whole sequence of vectors.
* sizeof(vector) < ELEN.  These could be scalar mat + a vector insert at ELEN etype.  Not always profitable depending on required constant mat cost on scalar side.
* Forming 128b constants with "cheap" i64 halfs.  We don't want to always use 64 bit scalar + insert idioms since general 64 bit constants are expensive, but for cases where we can materialize the halfs in one or two instructions, it's probably better than a constant pool load.  (Can also use two splats + merge idiom.)
* Few common bytes.  If a constant has only a handful of unique bytes, then using a smaller constant (made up only of those bytes) and a vrgather (with a new constant index vector) to shuffle bytes is feasible.  Only profitable if a) vrgather is cheap enough and b) cost of two new constants is low.
* Small constants values in large etype.  Can use vsext and vzext variants to reduce size of constant being materialized.  Combines with tricks (e.g. move from scalar) to make vectors with all lanes near zero significantly cheaper.  (e.g. <i32 -1, i32 0, i32 2, i32 1>, is sext <i8 -1, i8 0, i8 2, i8 1> to <4 x i32>, and thus a 32 bit constant + the extend cost)
* All the usual arithmetic tricks apply.  Probably only profitable on non-splat vectors, but could be useful for e.g. reducing number of active bits.

Note that many of these patterns aren't really constant specific, they're more build vector idioms appiled to constants.

Scalable Vectors in KnownBits (and friends)
===========================================

Scalable vectors had not been plumbed through known bits, demanded bits, or most of the other ValueTracking-esq routines.

I have a series of patches starting with https://reviews.llvm.org/D136470 (see the review stack) which adds basic lane wise reasoning.  Most of these have landed.  Once all of these land, there's a couple small todos:

* Add support for step_vector to all the routines touched above
* Complete the audit of all the target hooks and remove the bailouts one by one
* Fix the hexagon legalization problem seen in https://reviews.llvm.org/D137140 and add implicit truncation in SDAG's KnownBits
* Add splat_vector base cases (analogous to constant base cases) to all of the isKnownX routines in ValueTracking and SDAG.  This is more generic extension to handle shufflevector than anything else.
* Revisit insertelement handling, and be less conservative where possible.

Longer term, my last comment on that review describes the direction.  It's copied here for ease of reference.

For the record, let me sketch out where I think this might be going long term.

For scalable vectors, we have a couple of idiomatic patterns for representing demanded elements.

The first is a splat - which this patch nicely handles by letting us do lane independent reasoning on scalable vectors. This covers a majority of the cases I've noticed so far, and is thus highly useful to have in tree as we figure out next steps.

The second is sub_vector insert/extract. This comes up naturally in SDAG due to the way we lower fixed length vectors on RISCV (and, I think, ARM SVE.) This requires tracking a prefix of the demanded bits corresponding to the fixed vector size, and then a single bit smeared across remaining (unknown number of) lanes.

We could pick the prefix length in one of two ways:

* From the fixed vector being inserted or extracted.
* From the minimum known vector register size. This is more natural in DAG; at the IR layer, this requires combining the minimum vector length of a type which the minimum vscale_range value.

The third is scalar insert/extract. For indices under the minimum vector size, this reduces the former case. I don't yet know how common various runtime indices we can't prove in bounds are. One example we might see is the "end of vector - 1" pattern which comes e.g. from loop vectorization exit values. There may also be others. I don't yet really have a good sense here.

The fourth is generalized shuffle indices. (i.e. figuring out what lanes are demanded from a runtime shuffle mask) We're several steps from being able to talk about this concretely, and I'm not yet convinced we'll need anything here at all. If we do need to go here, this adds a huge amount of complexity. I'm hoping we don't get here.

I'm pretty sure we'll need to generalize at least as far as subvector insert/extract. I'm not sure about going beyond that yet.

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


-------------------------------------------------
Working Notes on RISCV Targeted Work in LLVM
-------------------------------------------------

This directory contains my *working notes*.  This is posted publicly to allow collaboration with other *active LLVM contributors*.  This is not intended to be any form of authoritative commentary on the target or the outstanding work.

If you are a new contributor looking for ideas, you're welcome to review these notes, but you should form your own opinion on the validity of implementing something here.  Please do *not* cite this repo for motivation in patches.  Nearly by definition, things listed here are observations and thoughts I had while working on something else, and *not the thing I considered high priority at the time*.  


2025-03-05, Spill and Immediate Refill
--------------------------------------

As noted on a recent review, we seem to have some cases where the register allocator is spilling a vector value to the stack, and then immediate loading it back into the same register.  (i.e. doing a completely redundant spill/fill)

Doing some grepping through the tests found this case.

.. code::

   ; RV32-NEXT:    vsrl.vi v16, v8, 4, v0.t
   ; RV32-NEXT:    addi a2, sp, 48
   ; RV32-NEXT:    vs8r.v v16, (a2) # Unknown-size Folded Spill
   ; RV32-NEXT:    vl8r.v v16, (a2) # Unknown-size Folded Reload
   ; RV32-NEXT:    vadd.vv v16, v8, v16, v0.t

With corresponds to:

.. code::

   define <32 x i64> @vp_ctlz_v32i64(<32 x i64> %va, <32 x i1> %m, i32 zeroext %evl) {
     %v = call <32 x i64> @llvm.vp.ctlz.v32i64(<32 x i64> %va, i1 false, <32 x i1> %m, i32 %evl)
     ret <32 x i64> %v
   }

And the command "./llc -mtriple=riscv32 -mattr=+v,+m < regalloc-spill-fill.ll"

Digging through the -print-after-all and -debug-only=isel, a couple of observations.  (Look for the vsrl just above the first vmul.)

.. code::

   %4:vr = COPY $v0
   ...
   ...

   $v0 = COPY %4:vr
   %66:vrm8nov0 = PseudoVSRL_VI_M8_MASK undef %66:vrm8nov0(tied-def 0), %64:vrm8nov0, 4, $v0, %190:gprnox0, 6, 1
   $v0 = COPY %4:vr
   %68:vrm8nov0 = PseudoVADD_VV_M8_MASK undef %68:vrm8nov0(tied-def 0), %64:vrm8nov0, %66:vrm8nov0, $v0, %190:gprnox0, 6, 1

Note that %4 is repeatedly copied into V0 here.  This is a case where moving vmv0 back through register allocation would make a huge difference in the constraint problem.

Next from the debug-only=isel trace:

.. code::

   selectOrSplit VR:%4 [32r,2208r:0) 0@32r  weight:1.058618e-02
   hints: $v0
   assigning %4 to $v0: V0 [32r,2208r:0) 0@32r
   ...
   selectOrSplit VRM8NoV0:%66 [2080r,2112r:0) 0@2080r  weight:4.629630e-03
   assigning %66 to $v16m8: V16 [2080r,2112r:0) 0@2080r V17 [2080r,2112r:0) 0@2080r V18 [2080r,2112r:0) 0@2080r V19 [2080r,2112r:0) 0@2080r V20 [2080r,2112r:0) 0@2080r V21 [2080r,2112r:0) 0@2080r V22 [2080r,2112r:0) 0@2080r V23 [2080r,2112r:0) 0@2080r
   ...
   evicting $v16m8 interference: Cascade 12
   unassigning %66 from $v16m8: V16 V17 V18 V19 V20 V21 V22 V23
   assigning %64 to $v16m8: V16 [1872r,2112r:0) 0@1872r V17 [1872r,2112r:0) 0@1872r V18 [1872r,2112r:0) 0@1872r V19 [1872r,2112r:0) 0@1872r V20 [1872r,2112r:0) 0@1872r V21 [1872r,2112r:0) 0@1872r V22 [1872r,2112r:0) 0@1872r V23 [1872r,2112r:0) 0@1872r
   queuing new interval: %66 [2080r,2112r:0) 0@2080r  weight:4.629630e-03
   Enqueuing %66
   ...
   selectOrSplit VRM8NoV0:%66 [2080r,2112r:0) 0@2080r  weight:4.629630e-03
   RS_Assign Cascade 12
   wait for second round
   queuing new interval: %66 [2080r,2112r:0) 0@2080r  weight:4.629630e-03
   Enqueuing %66
   ...
   selectOrSplit VRM8NoV0:%66 [2092r,2112r:0) 0@2092r  weight:4.629630e-03
   RS_Split Cascade 12
   Analyze counted 2 instrs in 1 blocks, through 0 blocks.
   Split around 2 individual instrs.
       enterIntvBefore 2092r: not live
       leaveIntvAfter 2092r: valno 0
       useIntv [2092B;2100r): [2092B;2100r):1
       skip:	2112r	%68:vrm8nov0 = PseudoVADD_VV_M8_MASK undef %68:vrm8nov0(tied-def 0), %210:vrm8, %66:vrm8nov0, $v0, %190:gprnox0, 6, 1
   Single complement def at 2100r
   Removing 0 back-copies.
     blit [2092r,2112r:0): [2092r;2100r)=1(%250):0 [2100r;2112r)=0(%249):0
     rewr %bb.2	2092r:1	%250:vrm8nov0 = PseudoVSRL_VI_M8_MASK undef %66:vrm8nov0(tied-def 0), %210:vrm8, 4, $v0, %190:gprnox0, 6, 1
     rewr %bb.2	2112B:0	%68:vrm8nov0 = PseudoVADD_VV_M8_MASK undef %68:vrm8nov0(tied-def 0), %210:vrm8, %249:vrm8nov0, $v0, %190:gprnox0, 6, 1
     rewr %bb.2	2092r:1	%250:vrm8nov0 = PseudoVSRL_VI_M8_MASK undef %250:vrm8nov0(tied-def 0), %210:vrm8, 4, $v0, %190:gprnox0, 6, 1
     rewr %bb.2	2100B:1	%249:vrm8nov0 = COPY %250:vrm8nov0
   Inflated %249 to VRM8
   queuing new interval: %249 [2100r,2112r:0) 0@2100r  weight:4.902913e-03
   Enqueuing %249
   queuing new interval: %250 [2092r,2100r:0) 0@2092r  weight:INF
   Enqueuing %250
   ...
   selectOrSplit VRM8:%249 [2100r,2112r:0) 0@2100r  weight:4.902913e-03
   RS_Spill Cascade 0
   Inline spilling VRM8:%249 [2100r,2112r:0) 0@2100r  weight:4.902913e-03
   From original %66
       also spill snippet %250 [2092r,2100r:0) 0@2092r  weight:INF
   Merged spilled regs: SS#17 [2092r,2112r:0) 0@x  weight:0.000000e+00
   spillAroundUses %249
       reload:   2116r	%251:vrm8 = VL8RE8_V %stack.17 :: (load unknown-size from %stack.17, align 8)
       rewrite: 2124r	%68:vrm8nov0 = PseudoVADD_VV_M8_MASK undef %68:vrm8nov0(tied-def 0), %210:vrm8, killed %251:vrm8, $v0, %190:gprnox0, 6, 1

   spillAroundUses %250
       rewrite: 2092r	%252:vrm8nov0 = PseudoVSRL_VI_M8_MASK undef %252:vrm8nov0(tied-def 0), %210:vrm8, 4, $v0, %190:gprnox0, 6, 1

       spill:   2096r	VS8R_V killed %252:vrm8nov0, %stack.17 :: (store unknown-size into %stack.17, align 8)


I'm very suspicious of the decisinn to split here.  I suspect (but have no fully convinced myself) that this is related to the "undef" tied def.  I think that's being treated as a use of %66, which seems inappropriate.  We split, and then immediate spill and fold the copy into the reload.

However, disabling that heuristic (via an #ifdef in local code) causes no change in the behavior.  We still fall through into the spilling logic and have exactly the same result.

Observations:

* We could try some kind of local redundant copy elimination - however doing so exposes either a) a bunch of rescheduling or b) if the scheduling is restricted allocation failures for FMAs.  We really do need vmv0 to survive into register allocation...
* The particular case being seen is compounded by a bad scheduling decision.  We're reordering the vlse before the vsrl/vadd sequence, thus greatly increasing register presure through the sequence.  This is a suspicious scheduling choice, but is mostly likely due to the issue in https://github.com/llvm/llvm-project/pull/126608 (which I really need to get back to.)
* For this particular example, we could use a vmv.v.x instead of the vlse.  This would help due to remat support.  See https://github.com/llvm/llvm-project/pull/130530.  This is a narrow fix for this issue, not a root issue.
   

2025-03-06, isAsCheapAsAMove and Remat
---------------------------------------

I've been looking at adding isAsCheapAsAMove to a few vector instructions, and ran into a bit of weirdness around rematerialization.  I think this might apply to the scalar side as well.  This is currently triggered by the following diff:

.. code::
   
   diff --git a/llvm/lib/Target/RISCV/RISCVInstrInfo.cpp b/llvm/lib/Target/RISCV/RISCVInstrInfo.cpp
   index f767223f96cd..c99280a7b29b 100644
   --- a/llvm/lib/Target/RISCV/RISCVInstrInfo.cpp
   +++ b/llvm/lib/Target/RISCV/RISCVInstrInfo.cpp
   @@ -1649,6 +1649,14 @@ bool RISCVInstrInfo::isAsCheapAsAMove(const MachineInstr &MI) const {
                MI.getOperand(1).getReg() == RISCV::X0) ||
               (MI.getOperand(2).isImm() && MI.getOperand(2).getImm() == 0);
      }
   +
   +  switch (RISCV::getRVVMCOpcode(MI.getOpcode())) {
   +  default:
   +    break;
   +  case RISCV::VID_V:
   +    return MI.getOperand(1).isUndef();
   +  }
   +
      return MI.isAsCheapAsAMove();
    }

   diff --git a/llvm/lib/Target/RISCV/RISCVInstrInfoVPseudos.td b/llvm/lib/Target/RISCV/RISCVInstrInfoVPseudos.td
   index 6d3c005583c2..e5728afe18ea 100644
   --- a/llvm/lib/Target/RISCV/RISCVInstrInfoVPseudos.td
   +++ b/llvm/lib/Target/RISCV/RISCVInstrInfoVPseudos.td
   @@ -6686,7 +6686,7 @@ defm PseudoVIOTA_M: VPseudoVIOTA_M;
    //===----------------------------------------------------------------------===//
    // 15.9. Vector Element Index Instruction
    //===----------------------------------------------------------------------===//
   -let isReMaterializable = 1 in
   +let isReMaterializable = 1, isAsCheapAsAMove = 1 in
    defm PseudoVID : VPseudoVID_V;
    } // Predicates = [HasVInstructions]


   diff --git a/llvm/test/CodeGen/RISCV/rvv/stepvector.ll b/llvm/test/CodeGen/RISCV/rvv/stepvector.ll
   index 62339130678d..64b4ce0ecdad 100644
   --- a/llvm/test/CodeGen/RISCV/rvv/stepvector.ll
   +++ b/llvm/test/CodeGen/RISCV/rvv/stepvector.ll
   @@ -533,13 +533,14 @@ define <vscale x 16 x i64> @stepvector_nxv16i64() {
    ; RV32-NEXT:    addi sp, sp, -16
    ; RV32-NEXT:    .cfi_def_cfa_offset 16
    ; RV32-NEXT:    csrr a0, vlenb
   +; RV32-NEXT:    addi a1, sp, 8
    ; RV32-NEXT:    sw a0, 8(sp)
    ; RV32-NEXT:    sw zero, 12(sp)
   -; RV32-NEXT:    addi a0, sp, 8
   -; RV32-NEXT:    vsetvli a1, zero, e64, m8, ta, ma
   -; RV32-NEXT:    vlse64.v v16, (a0), zero
   +; RV32-NEXT:    vsetvli a0, zero, e64, m8, ta, ma
   +; RV32-NEXT:    vlse64.v v8, (a1), zero
   +; RV32-NEXT:    vid.v v16
   +; RV32-NEXT:    vadd.vv v16, v16, v8
    ; RV32-NEXT:    vid.v v8
   -; RV32-NEXT:    vadd.vv v16, v8, v16
    ; RV32-NEXT:    addi sp, sp, 16
    ; RV32-NEXT:    .cfi_def_cfa_offset 0
    ; RV32-NEXT:    ret
   @@ -550,6 +551,7 @@ define <vscale x 16 x i64> @stepvector_nxv16i64() {
    ; RV64-NEXT:    vsetvli a1, zero, e64, m8, ta, ma
    ; RV64-NEXT:    vid.v v8
    ; RV64-NEXT:    vadd.vx v16, v8, a0
   +; RV64-NEXT:    vid.v v8
    ; RV64-NEXT:    ret
      %v = call <vscale x 16 x i64> @llvm.stepvector.nxv16i64()
      ret <vscale x 16 x i64> %v


The whole rest of this is triggered by the question "Why do we duplicate the vid.v at the end of the RV64 check"?  This doesn't appear to be profitable.  We're just increasing dynamic instruction count with no benefit.

This seems to be triggered by the "abi copy" we emit for the return value.  As background, we tend to emit copies to physical registers for ABI related reasons (i.e. returns and arguments).  We also happen to do so for the V0 case on masked vector instructions.

I surprised to learn that register coalescer will rematerialize isAsCheapAsAMove instructions directly into physical register results.. The root issue is that the materialization (via reMaterializeTrivialDef) appears to apply any *profitability* analysis.  It just blindly duplicate.  This would be fine under the assumption that these copies were "real", but they're very frequently not.  The register allocator is frequently able to allocate defining values into the ABI registers without an extra copy. The net effect is that we end up increasing dynamic icount for no reason.

I tried to implement a quick and dirty heuristic to only rematerialize when the definition register had one use.  Not entirely surprisingly, this caused both improvements and regressions (including extra stack spills in a couple cases).  I tested this only *without* the VID patch above (i.e. looking at scalar effects).

Tentative conclusions:

* Blindly rematerializing in reg coalescing probably isn't the right place to do it.  We need some kind of profitability check here, but can't do so in practice until the next item is resolved.
* We appear to be missing rematerialization at some later point - i.e. disabling it in register coalescing results in a failure to rematerialize at all.  From prior knowledge, I'm guessing the gap is in the splitter (since I know InlineSpiller does remat.)  This is likely a relatively large chunk of work, but may be warranted/needed.
* Avoiding unneeded copies to the physical registers (i.e. VMV0 to V0) will likely help reduce some noise for the generic vector remat via isAsCheapAsAMove changes, but might also inhibit rematerialization in some cases for the same reasons.

As an aside, note that MachineSink will also do rematerialization directly into a physical register (via PerformSinkAndFold).  However, this one does require that the original instruction be removeable, and isn't problematic in the same way as above.  In at least one case, I did see it expose a problem in VLOptimizer.  The symbom in VLOptimizer was that we failed following assert because we had a physical register not a virtual one.

.. code::

   assert(MI.getOperand(0).isReg() &&
          isVectorRegClass(MI.getOperand(0).getReg(), MRI) &&
          "All supported instructions produce a vector register result");

I went back to extract a reproducer, and things had shifted enough I couldn't easily reproduce.  I don't know the issue has been fixed


2025-03-10, Spill and Immediate Refill continued
------------------------------------------------

Picking up from above, with a new test case as the vmv.v.x change "fixed"
the prior one.

.. code::

   define <vscale x 16 x double> @vp_round_nxv16f64(<vscale x 16 x double> %va, <vscale x 16 x i1> %m, i32 zeroext %evl) {
     %v = call <vscale x 16 x double> @llvm.vp.round.nxv16f64(<vscale x 16 x double> %va, <vscale x 16 x i1> %m, i32 %evl)
     ret <vscale x 16 x double> %v
   }

Tracing through the print-after-all and debug-only=regalloc, the interesting
bit in this one is:

.. code::

   selectOrSplit VRM8NoV0:%24 [48r,560r:0)[560r,912r:1) 0@48r 1@560r  weight:4.794304e-03
   hints: $v16m8
   assigning %24 to $v16m8: V16 [48r,560r:0)[560r,912r:1) 0@48r 1@560r V17 [48r,560r:0)[560r,912r:1) 0@48r 1@560r V18 [48r,560r:0)[560r,912r:1) 0@48r 1@560r V19 [48r,560r:0)[560r,912r:1) 0@48r 1@560r V20 [48r,560r:0)[560r,912r:1) 0@48r 1@560r V21 [48r,560r:0)[560r,912r:1) 0@48r 1@560r V22 [48r,560r:0)[560r,912r:1) 0@48r 1@560r V23 [48r,560r:0)[560r,912r:1) 0@48r 1@560r

   selectOrSplit VRM8NoV0:%36 [64r,880r:0)[880r,896r:1) 0@64r 1@880r  weight:4.918831e-03
   hints: $v8m8
   assigning %36 to $v8m8: V8 [64r,880r:0)[880r,896r:1) 0@64r 1@880r V9 [64r,880r:0)[880r,896r:1) 0@64r 1@880r V10 [64r,880r:0)[880r,896r:1) 0@64r 1@880r V11 [64r,880r:0)[880r,896r:1) 0@64r 1@880r V12 [64r,880r:0)[880r,896r:1) 0@64r 1@880r V13 [64r,880r:0)[880r,896r:1) 0@64r 1@880r V14 [64r,880r:0)[880r,896r:1) 0@64r 1@880r V15 [64r,880r:0)[880r,896r:1) 0@64r 1@880r

   selectOrSplit VR:%30 [32r,736e:0)[736e,848r:1) 0@32r 1@736e  weight:7.475329e-03
   hints: $v0
   missed hint $v0
   Analyze counted 8 instrs in 2 blocks, through 1 blocks.
   $v0	no positive bundles
   assigning %30 to $v24: V24 [32r,736e:0)[736e,848r:1) 0@32r 1@736e

   selectOrSplit VR:%18 [288r,416e:0)[416e,528r:1) 0@288r 1@416e  weight:1.262500e-02
   hints: $v0
   missed hint $v0
   Analyze counted 7 instrs in 1 blocks, through 0 blocks.
   $v0	no positive bundles
   assigning %18 to $v25: V25 [288r,416e:0)[416e,528r:1) 0@288r 1@416e

   ...
   
   selectOrSplit VRM8NoV0:%14 [368r,416r:0) 0@368r  weight:4.464286e-03
   RS_Split Cascade 0
   Analyze counted 2 instrs in 1 blocks, through 0 blocks.
   Inline spilling VRM8NoV0:%14 [368r,416r:0) 0@368r  weight:4.464286e-03
   From original %14
   Merged spilled regs: SS#0 [368r,416r:0) 0@x  weight:0.000000e+00
   spillAroundUses %14
       rewrite: 368r	%49:vrm8nov0 = PseudoVFSGNJX_VV_M8_E64_MASK undef %49:vrm8nov0(tied-def 0), %24:vrm8nov0, %24:vrm8nov0, $v0, %13:gprnox0, 6, 3

       spill:   376r	VS8R_V killed %49:vrm8nov0, %stack.0 :: (store unknown-size into %stack.0, align 8)
       reload:   392r	%50:vrm8nov0 = VL8RE8_V %stack.0 :: (load unknown-size from %stack.0, align 8)
       rewrite: 416r	early-clobber %18:vr = nofpexcept PseudoVMFLT_VFPR64_M8_MASK %18:vr(tied-def 0), killed %50:vrm8nov0, %17:fpr64, $v0, %13:gprnox0, 6, 1

   Inflated %50 to VRM8
   queuing new interval: %49 [368r,376r:0) 0@368r  weight:INF
   Enqueuing %49
   queuing new interval: %50 [392r,416r:0) 0@392r  weight:INF
   Enqueuing %50

Note that this is with tryInstructionSplit disabled due to the same red-herring
as above.

Interesting observations here:

* It's surprising that neither v24 or v25 can be assigned to v0.  Looking at the MIR, this comes down a vmflt with both a mask and tied use.  We have the def marked early clobber (required to avoid overlap with the vector source), but the overlap rules for this instruction *do* allow overlap with v0.  Craig had previously suggested adding another pseudo for this case, and this seems worthwhile here.
* The major point is why didn't we evict the v24, and v25?  The answer to that comes down to spill weight.  We don't think the m8 for %14 costs enough to be worth evicting the two m1 values - despite the fact they can be freely reassigned.
* There's two sub-issues in that.  The first is that our spill weights are not accouting for the true cost of spilling the vector register group.  I mocked up a local patch, but finally realized I'd rediscovered https://github.com/llvm/llvm-project/pull/113675.
* The second is that eviction doesn't appear to be taking the "cost" of the eviction into account.  This particular case, we can reassign as zero cost and thus should probably adjust the allocation for *any* other blocked allocation.  It's odd we don't do that.
* In terms of allocation order, there's also a question of why we assigned v24, v25 and not say v7, v6.  I believe this simply comes down to the allocation order we chose for m1, which tries to avoid fragmenting the first register in each register group.  Maybe we tried a bit too hard there?  Or should use a different allocation if we know that v0-v7 is already fragamented?  (via a v0 use for instance...)
* In a different take, I'm not sure that all the masking here is functionally required.  I thought in the default C environment, we had some freedom on when NaNs were reported.  Maybe we could loosen some constraints here?

As an aside, when looking at the diff from the spill weights change, I noticed that explode_16x64 had a case where we're extracting the low element of a m8 vsrl.  It looks like we could reduce the width of shift to m1.  I might have missed an extra use though; I didn't look too hard.


2025-03-14, Re-analysis of above
--------------------------------

After the spill weight and vmv.v.x on rv32 changes, taking a new look at the previous test cases.

vp_round_nxv16f64 is much improved.  It still has the vmflt issue, and we should pick that off and fix it just for code quality.  (i.e. we end up with some redundant mask copies for no purpose.)  The likely scheme involves an additional pseudo for this case.  

vp_ctlz_v32i64 is much improved on rv64, but still shows a bunch of spilling on rv32.  The interesting cases are all triggered by performing SEW64 operations on rv32 and thus being unable to use .vx forms for most things.  Some observations from that one:

* The value we're and-ing by is a byte mask - that is, it's conditionally zeroing individual bytes.  It's also repeating i32 halves.  As a result, we could avoid the vmv.v.x entirely by either switching VTYPE to SEW8 and using a vmerge.vxm w/zero and different mask, or by switching to SEW32 and using half the mask.  Note that the later would allow use of the .vx form.  Either of these might be worthwhile, but are rv32 specific optimizations.  On rv64, the vtype toggle probably isn't worth the two scalar instructions saved.
* There's a rematerialization issue with the vmv.v.x at SEW64.  Why isn't the vmv.v.x being rematerialized?  Spilling (the current behavior) is definitely net worse.   More on this below.

Tracing through the the InlineSpiller, and LiveRangeEdit, the thing that's preventing the rematerialization is that the GPRs operand to the vmv.v.x has a very short live range.  LiveRangeEdit checks in allUsesAvailableAt that the VNI at the use site matches the definition, and in this case, there is no VNI for the use site.  This is "correct", but a bit odd given that a) this is during vector regalloc, and b) the scalar statically dominates the use site.  If I relax this check in a hack, this test case does rematerialize properly.

Ideas:

* Special case registers which aren't in the register classes currently being allocated in split register allocation?  Would fix the vmv.v.x case, but feels a bit suspect.  Does require callers to update liveness.  Another approach, but still restricted to split alloc, is to spurious extend all the scalar ranges before vector regalloc, and then shrink to uses afterwards.
* Allow extending liveness for vregs only.  Doing this is fairly trivial, but it means remat is allocation order sensative.
* Extend vregs and previously allocated registers with no-use of the register before the new use.  Partially solves the allocation order problem, but only partly.  (The result might be more optimal if the GPR is reallocated to a different register.)
* In this example, the scalar instruction is itself rematerializable.  Instead of updating liveness, we could force materialize the scalar sequence?  Doing that doesn't actually look to hard in the existing interface.  However, there's definitely a profitability question here.  On the other hand, the general ability to remat multiple instruction sequences (e.g. LUI/ADDI) seems super useful...

Other off topic observations:

* The use of masking in this entire sequence is questionable.  We could instead do a single mask at the end to preserve the lanes in the passthru.  This would reduce the register pressure through the sequence by one m8 register, which would help slightly with the remat problems.  However, in the rv64 case the masking happens to work out well, and we'd actually introduce 2 additional spill/fills for that.
* A slightly crazy idea would be to teach the register allocator how to "split" high LMUL operations.  In this case, if we split to m4 (instead of m8), the mask values shrink porportionately.  I think at m4 we'd allocate cleanly.  We'd definitely do so at e.g. m2 or m1.
* Another thing we could do is to "split" the vmv.v.x splat into a "m1 splat" followed by a series of whole register moves.  This might expose to the register allocator that only one vreg of the register group needs to be allocated until late.  We could merge this back into an m8 splat late, potentially.  This could also be a vmv.s.x and a vrgather.vi if that was easier - from a vtype toggle perspective.

This looks complicated, no matter which option we chose.


2025-06-15, Vector Code Gen in TSCV_2
-------------------------------------

Some of these are copied from older notes (consolidating written ones), some are new observations.

Masking
========

Looking at masked predication primarily.  

*s1115*

Has a unit strided load which is not being recognized.  Appears to be due to gather-scater-lowering seeing two vector indices on a gep when one of them is a splat.  Fixed this in instcombine, but there's still a open question of why loop-vectorizer wasn't recognizing the unit strided load instead of emitting a gather in this case.

This appears to be distinct from the rerolling cases as we get a single masked.load in this case.

*s112 but also many others*

We materialize the address of globals used by the dummy call outside the nested loop which creates some very long live ranges.  The dummy call is inside the outer loop of the nest which is somewhat high trip count, so this isn't insane.

We could definitely sink the ADDIs into the loop (as we have to insert mv to put them into argument registers anyway).  Given the size of the arrays, and the small offset into the ADDI, it's not clear that e.g. global-merge could eliminate address copies or anything.  Probably worth a slightly closer look, but nothing immediately obvious?

Hm, at least some of the addresses are being spilled.  But only in a few functions (e.g. s2102)  Why aren't we rematerializing these instead?  Also, looks like maybe some LSR choices are sub-optimal in that inner loop resulting in larger scalar register pressure?

Another slightly crazy idea - would spilling to FP registers be better than spilling to stack?  We've got a bunch of free floating point registers in s2102.

Small, but it looks like we might not be remating "fmv.w.x fs0, zero" and inserting a copy just before the dummy call instead.  Still in s2102.

On the other hand, the function name constants are tiny.  We already rematerialize the address so that we don't have a long live range (and emit a tail call for the calc_checksum - cool) - but do we have any room for packing these before the function or something?

Alternatively, some kind of global merge + wrapper stub for calc_checksum and initialize_arrays could take only the offset into the merged table?  This would be a codesize win at best in this case.

*masked interleave*

When looking into tail folding, I noticed we weren't forming interleave groups in TSVC.  The obvious fix was that we were missing a TTI hook, but doing that reveals a few related problems.

* InterleavedAccessPass doesn't handle masked.load or masked.store.
* getInterleavedMemOperationCost doesn't handle masked scalable cases in the fallback path (it could by costing he intrinsics)
* The mask generation for the tail folded fixed vector case is terrible.  (And the scalable is probably worse.)
* When all of the above is fixed, interleavedAccessCanBeWidened has a power of two bailout which needs removed.

I added some basic tests in a85525f87. 

Default
=======

This is coming from a pass looking at the default (non tail folded) vectorization for these loops with fastmath.

*s110*

* we have a case where we perform a reduce of an fadd fed by a strided_load + a reversed normal load.  We're currently materializing the reverse, but could fold the reverse into the stride on the other operand of the fadd.
* Also , why do we have an inloop reduction here at all?  With fastmath this should be an out of loop reduction?

*s2101*

We have the following sequence::
  	vadd.vx	v20, v12, s11
	vadd.vv	v20, v20, v16
	vsetvli	zero, zero, e32, m2, ta, ma
	vluxei64.v	v24, (zero), v20

In the above, s11 should be folded into base operand of vluxei64

Looking at the IR, we have geps of the following form::
   %5 = getelementptr inbounds nuw [256 x [256 x float]], ptr @bb, i64 0, <vscale x 4 x i64> %vec.ind, <vscale x 4 x i64> %vec.ind

%vec.ind appears to be a canonical vector IV advancing by a fixed stride.  I haven't stared at this yet, but it seems very likely we can improve the indexing of this case.


*s442*

Looking at the vluxei64 addressing, it looks like this would be a strided load except that here are two different base pointers for the elements.

We can definitely improve the strided part of the addressing in this case (by adding the step * scale) and avoid one shift.

We might be able to do something fancy with two masked strided loads, but not sure if that's worthwhile?

EVL
===

The widening induction issue still results in too many cases of missed optimization to make the code generation particularly interesting.

*s112 and s1112*

We were previously failing to remove vp.reverse pairs, but that has now been fixed.  There is likely still room to improve vp.reverse of mask genration; not bitreverse per se (nothing obvious to do there without zvbb), but the actual mask generation sequence.

We also had a costing issue with reverse costing being quadratic vs linear, but that's now fixed and we've chosen a more natural vectorization factor.

*blend*

If we have a control flow merge managed via a VPBlend, this isn't getting rewriten using EVL.  As a result, we end up with uses of the header mask which are removable.

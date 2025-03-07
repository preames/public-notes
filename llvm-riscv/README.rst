-------------------------------------------------
Working Notes on RISCV Targeted Work in LLVM
-------------------------------------------------

This directory contains my *working notes*.  This is posted publicly to allow collaboration with other *active LLVM contributors*.  This is not intended to be any form of authoritative commentary on the target or the outstanding work.

If you are a new contributor looking for ideas, you're welcome to review these notes, but you should form your own opinion on the validity of implementing something here.  Please do *not* cite this repo for motivation in patches.  Nearly by definition, things listed here are observations and thoughts I had while working on something else, and *not the thing I considered high priority at the time*.  



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

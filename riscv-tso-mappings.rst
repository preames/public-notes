-----------------------------
TSO Memory Mappings for RISCV
-----------------------------

This document lays out the memory mappings being proposed for Ztso.  Specifically, these are the mappings from C/C++ memory models to RISCV w/Ztso.  This document is a placeholder until this can be merged into something more official.

The proposed mapping tables are the work of Andrea Parri.  He's an actual memory model expert; I'm just a compiler guy who has gotten a bit too close to these issues, and needs to drive upcoming patches for LLVM.  As always, mistakes are probably mine, and all credit goes to Andrea.  

.. contents::

Proposed Mapping
----------------

The proposed mapping table is:

.. code::

   C/C++ Construct                          | RVTSO Mapping
   ------------------------------------------------------------------------------
   Non-atomic load                          | l{b|h|w|d}
   atomic_load(memory_order_relaxed)        | l{b|h|w|d}
   atomic_load(memory_order_acquire)        | l{b|h|w|d}
   atomic_load(memory_order_seq_cst)        | fence rw,rw ; l{b|h|w|d}
   ------------------------------------------------------------------------------
   Non-atomic store                         | s{b|h|w|d}
   atomic_store(memory_order_relaxed)       | s{b|h|w|d}
   atomic_store(memory_order_release)       | s{b|h|w|d}
   atomic_store(memory_order_seq_cst)       | s{b|h|w|d}
   ------------------------------------------------------------------------------
   atomic_thread_fence(memory_order_acquire)    | nop
   atomic_thread_fence(memory_order_release)    | nop
   atomic_thread_fence(memory_order_acq_rel)    | nop
   atomic_thread_fence(memory_order_seq_cst)    | fence rw,rw
   ------------------------------------------------------------------------------
   C/C++ Construct                          | RVTSO AMO Mapping
   atomic_<op>(memory_order_relaxed)        | amo<op>.{w|d}
   atomic_<op>(memory_order_acquire)        | amo<op>.{w|d}
   atomic_<op>(memory_order_release)        | amo<op>.{w|d}
   atomic_<op>(memory_order_acq_rel)        | amo<op>.{w|d}
   atomic_<op>(memory_order_seq_cst)        | amo<op>.{w|d}
   ------------------------------------------------------------------------------
   C/C++ Construct                          | RVTSO LR/SC Mapping
   atomic_<op>(memory_order_relaxed)        | loop: lr.{w|d} ; <op> ;
                                            |       sc.{w|d} ; bnez loop
   atomic_<op>(memory_order_acquire)        | loop: lr.{w|d} ; <op> ;
                                            |       sc.{w|d} ; bnez loop
   atomic_<op>(memory_order_release)        | loop: lr.{w|d} ; <op> ;
                                            |       sc.{w|d} ; bnez loop
   atomic_<op>(memory_order_acq_rel)        | loop: lr.{w|d} ; <op> ;
                                            |       sc.{w|d} ; bnez loop
   atomic_<op>(memory_order_seq_cst)        | loop: lr.{w|d}.aqrl ; <op> ;
                                            |       sc.{w|d} ; bnez loop

The key thing to note here is that we using an fence *before* any seq_cst *load*.  There is an alternative mapping (discussed below) which uses a fence *after* an atomic *store*.  The mapping shown here is the one I am proposing moving forward with.

The alternate mapping
---------------------

This mapping table is listed here for explanatory value only.  This lowering is **incompatible** with the mapping proposed for inclusion in toolchains and psABI (above).

.. code::

   C/C++ Construct                          | RVTSO Mapping
   ------------------------------------------------------------------------------
   Non-atomic load                          | l{b|h|w|d}
   atomic_load(memory_order_relaxed)        | l{b|h|w|d}
   atomic_load(memory_order_acquire)        | l{b|h|w|d}
   atomic_load(memory_order_seq_cst)        | l{b|h|w|d}
   ------------------------------------------------------------------------------
   Non-atomic store                         | s{b|h|w|d}
   atomic_store(memory_order_relaxed)       | s{b|h|w|d}
   atomic_store(memory_order_release)       | s{b|h|w|d}
   atomic_store(memory_order_seq_cst)       | s{b|h|w|d} ; fence rw,rw
   ------------------------------------------------------------------------------
   atomic_thread_fence(memory_order_acquire)    | nop
   atomic_thread_fence(memory_order_release)    | nop
   atomic_thread_fence(memory_order_acq_rel)    | nop
   atomic_thread_fence(memory_order_seq_cst)    | fence rw,rw
   ------------------------------------------------------------------------------
   C/C++ Construct                          | RVTSO AMO Mapping
   atomic_<op>(memory_order_relaxed)        | amo<op>.{w|d}
   atomic_<op>(memory_order_acquire)        | amo<op>.{w|d}
   atomic_<op>(memory_order_release)        | amo<op>.{w|d}
   atomic_<op>(memory_order_acq_rel)        | amo<op>.{w|d}
   atomic_<op>(memory_order_seq_cst)        | amo<op>.{w|d}
   ------------------------------------------------------------------------------
   C/C++ Construct                          | RVTSO LR/SC Mapping
   atomic_<op>(memory_order_relaxed)        | loop: lr.{w|d} ; <op> ;
                                            |       sc.{w|d} ; bnez loop
   atomic_<op>(memory_order_acquire)        | loop: lr.{w|d} ; <op> ;
                                            |       sc.{w|d} ; bnez loop
   atomic_<op>(memory_order_release)        | loop: lr.{w|d} ; <op> ;
                                            |       sc.{w|d} ; bnez loop
   atomic_<op>(memory_order_acq_rel)        | loop: lr.{w|d} ; <op> ;
                                            |       sc.{w|d} ; bnez loop
   atomic_<op>(memory_order_seq_cst)        | loop: lr.{w|d} ; <op> ;
                                            |       sc.{w|d}.aqrl ; bnez loop

The key difference to note is that this lowering uses an fence *after* the sequentially consistent stores,

Discussion
----------

So, why are we proposing the first mapping and not the alternative?  This comes down to a benefit analysis.

The proposed Ztso mapping was constructed to be a strict subset of the WMO mapping.  Consider the case where we are running on a Ztso machine, but that not all of our object files or libraries were compiled assuming Ztso.  If the Ztso mapping is a subset of the WMO mapping, then all parts of this mixed application include the required fences for correctness on Ztso.  Some libraries might have a bunch of redundant fences (i.e. all the ones needed by WMO not needed for Ztso), but the application will behave correctly regardless.  This allows libraries targeted for WMO to be reused on a Ztso machine with only selective performance sensitive pieces selectively recompiled explicitly for ZTso.

The alternative mapping instead parallels the mappings used by X86.  Ztso is intended to parallel the X86 memory model, and it is desirable if explicitly fenced code ported from x86 just worked with Ztso.  Consider a developer who is doing a port of a library which is implemented using normal C intermixed with either inline assembly or intrinsic calls to generate fences.  If that code follows the x86 convention, then a naive port will match the alternate mapping.  The key point is that code using the alternate mapping will not properly synchronize with code compiled with the proposed mapping.

To avoid confusion, let me emphasize that the porting concern just mentioned *does not* apply to code written in terms of either C or C++'s explicit atomic APIs.  Instead, it *only* applies to manually ported assembly or code which is already living dangerously by using explicit fencing around relaxed atomics.  Such code is rare, and usually written by experts anyways.  The slightly broader class of code which may be concerning is that with non-atomic loads and stores mixed with explicit fencing.  Such code is already relying on undefined behavior in C/C++, but "probably works" on X86 today and might not after a naive RISCV port if synchronizing with code compiled with the proposed mapping.

The alternative mapping also has the advantage that stores are generally dynamically rarer than loads.  So the alternative mapping *may* result in dynamically fewer fence instructions.  I do not have numbers on this.

The choice between the two mappings essentially comes down to which of these we consider to be more important.  I am proposing we move forward with the mapping which gives us WMO comparability.  It is my belief that allowing mixed applications is more important to the ecoyststem then ease of porting explicit synchronization.  

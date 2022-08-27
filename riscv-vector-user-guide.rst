-------------------------------
Using RISCV Vector Instructions
-------------------------------

This is intended to be a user focused guide on how to leverage vector instructions on RISCV.  Most of what I can find on the web is geared towards vector before v1.0 was ratified, and there's enough differences that having something to point people to has proven useful.

.. contents::


Execution Environments
----------------------

qemu-riscv32/64 support the v1.0 vector extension in upstream.  Note that the default packages available in most distros are not recent enough.  You will need to download qemu and build from source.  Thankfully, this is pretty straight forward, and `qemu's build instructions <https://wiki.qemu.org/Hosts/Linux>`_ are sufficiently up to date.

Once you have a sufficiently recent qemu-riscv, you should be able to run binaries containing vector instructions.  Note that vector is not enabled by qemu-user by default at this time, so you will need to explicitly enable it.  If you get unhelpful error output when doing so, you are most likely using a version of qemu which is too old.  

With qemu-user, you can run and test programs in a cross build environment with one major gotcha.  glibc does not have mcontext/ucontext support for vector, so anything which requires them - e.g. longjmp, signals, green threads, etc - will fail in interesting and unexpected ways.

**WARNING**: At the moment, support for the vector extension has *NOT* landed in upstream Linux kernel, and I am not aware of any distro which currently applies the required patches.  So, unless you are running a custom kernel, there is a *very* good chance you can't run a native environment.

   If you try, you will most likely get an illegal instruction exception (SIGILL) on the first vector instruction you execute.  In many programs - though not all - this will look like a SIGILL on the first access to a vector CSR (e.g. `csrr a2, vlenb`) or a vector configuration instruction (e.g. `vsetvli	a1, zero, e32, m1, ta, mu`).  

**Said differently, unless you're running a patched kernel, you can not enable vector code even if your hardware supports it!**


Assembler Support
------------------

The LLVM assembler fully supports for v1.0 vector extension specification, and has for a while.  Using the 15.x release branch is definitely safe, and older release branches may also work.

The binutil's assembler used by GNU also supports the v1.0 vector extension since `the 2.38 release <https://sourceware.org/pipermail/binutils/2022-August/122594.html>`_  (released Feb 2022).

Compiler Support
----------------

Enabling Vector Codegen on LLVM/Clang
=====================================

This section is describing the behavior of current upstream development tip-of-tree.  This is an area under very heavy churn.  These instructions will probably work on LLVM 15.0 (once released); using prior versions is strongly not advised.

You need to make sure to explicitly tell the compiler (via `-mattr=...,+v`) to enable vector code lowering.  If you don't, you may be get compiler errors (i.e. use of vector types rejected), you may see code being scalarized by the backend, or (hopefully not) you may stumble across internal compiler errors.

For fixed length vectors, default behavior very recently (2022-08-26) changed.  As of now, fixed length vectors are enabled by the presence of the vector instructions (e.g. `-mattr=...,+v`).  You can disable via `-mllvm -riscv-v-vector-bits-min=0`.  Note that this is an internal compiler flag, and not a documented interface which will be supported long term.  Be cautious of adding this to any build command which is not easy to change as you move to a new compiler version.

**Warning**: The flags mentioned above also have the effect of enabling auto-vectorization; if this is undesirable, consider `-fno-vectorize` and `-fno-slp-vectorize`.  Vectorizer user documention can be found `here <https://llvm.org/docs/Vectorizers.html>`_.

Enabling Vector Codeen on GNU
=============================

I am unclear on the status of GNU support for vector.  I believe the situation to be that upstream GNU does not support vector at all, but that the `RISC-V collab version <https://github.com/riscv-collab/riscv-gnu-toolchain>`_ does.  I could not find any documentation on this point, so this is pending experimental confirmation.


Intrinsics and Explicit Vector Code
===================================

The RVV C Intrinsic family is fully supported by Clang.  You can also use Clang's `vector type and operation extensions <https://clang.llvm.org/docs/LanguageExtensions.html#vectors-and-extended-vectors>`_ to describe vector operations in C/C++.

Auto-vectorization
==================

I have been actively working to improve the state of auto-vectorization in LLVM for RISC-V.  If you're curious about the details, see `my working notes <https://github.com/preames/public-notes/blob/master/llvm-riscv-status.rst#vectorization>`_.  The following is a user focused summary of where we stand right now.  This is an area of extremely heavy change, so please keep in mind that this snapshot is very specific to the current moment in time, and is likely to continue changing.

The LLVM 15 release branch contains all of the changes required for functional auto-vectorization via the LoopVectorizer, but (intentionally) does not contain the change to enable it by default.  Tip of tree LLVM contains multiple changes to improve the performance robustness of LoopVectorization vectorization, and enables vectorization via both scalable and fixed vectors when vector codegen is enabled (see above).  If you're interested in this area, it is strongly recommended that you build LLVM from (very recent!) source.  If you wish to enable vectorization on the release branch for experimental purposes, you need to specify `-mllvm -scalable-vectorization=on`.  Note that this is an internal compiler option, and will not be supported.  Any bugs found will only be fixed on tip-of-tree, and will not be backported.  The current expectation is that auto-vectorization will be supported in the 16.x release series, but that's subject to change.

For SLPVectorizer, the additional compiler flag `-mllvm -riscv-v-slp-max-vf=0` is required.  This configuration is under vecy active development, and should only be considered on a build of recent ToT source.

For GNU, I am not aware of any GNU build which contains auto-vectorization support at this time.














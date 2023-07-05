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

Enabling Vector Codegen
=======================

Vector code generation has been supported since (at least) LLVM 15.0.  I've been told by gcc developers that upstream GNU does support vector code generation as of (at least) gcc 13.

You need to make sure to explicitly tell the compiler (via `-mattr=...,+v`) to enable vector code lowering.  If you don't, you may be get compiler errors (i.e. use of vector types rejected), you may see code being scalarized by the backend, or (hopefully not) you may stumble across internal compiler errors.

**Warning**: The flag mentioned above also have the effect of enabling auto-vectorization; if this is undesirable, consider `-fno-vectorize` and `-fno-slp-vectorize`.  Vectorizer user documention can be found `here <https://llvm.org/docs/Vectorizers.html>`_.

Intrinsics and Explicit Vector Code
===================================

The `gcc vector extension syntax <https://gcc.gnu.org/onlinedocs/gcc/Vector-Extensions.html>`_ is fully supported by both GCC and Clang.  This is a good way of writing explicitly fixed length vector code in C/C++.

The RVV C Intrinsic family is fully supported by Clang and GCC.  This is currently the main way to write explicit length agnostic vector code.  

For clang, the `#pragma clang loop <https://clang.llvm.org/docs/LanguageExtensions.html#extensions-for-loop-hint-optimizations>`_ directives can be used to override the vectorizers default heuristics.  This can be very useful for exploring performance of various vectorization options.

.. code::

  // Let's force LMUL4 with unroll factor of 2.
  #pragma clang loop vectorize(enable)
  #pragma clang loop interleave(enable)
  #pragma clang loop vectorize_width(8, scalable)
  #pragma clang loop interleave_count(2)
  for (unsigned i = 0; i < a_len; i++)
    a[i] += b;


Auto-vectorization
==================

I have been actively working to improve the state of auto-vectorization in LLVM for RISC-V.  If you're curious about the details, see `my working notes <https://github.com/preames/public-notes/blob/master/llvm-riscv-status.rst#vectorization>`_.  The following is a user focused summary of where we stand right now.  This is an area of extremely heavy churn, so please keep in mind that this snapshot is very specific to the current moment in time, and is likely to continue changing.

The LLVM 16 release branch contains all of the changes required for auto-vectorization via the LoopVectorizer via both scalable and fixed vectors when vector codegen is enabled (see above).

For SLPVectorizer, use of a very recent tip of tree is recommended.  SLP has recently been enabled by default in trunk, and is on track to be enabled in the 17.x release series, but that's subject to change.  If you're interested in this area, it is strongly recommended that you build LLVM from (very recent!) source.  If you wish to enable SLP vectorization on the 16.x release branch for experimental purposes, you need to specify `-mllvm -riscv-v-slp-max-vf=0`.  Note that this is an internal compiler option, and will not be supported.  Any bugs found will only be fixed on tip-of-tree, and will not be backported.

For gcc, patches to support auto-vectorization have recently started landing.  There's very active development going on with multiple contributors, so the exact status is hard to track.  Hopefully, the gcc-14 release notes will contain information about what is and is not supported.

T-Head `has a custom toolchain <https://occ.t-head.cn/community/download?id=4090445921563774976>`_ which may suppport vectorization as their processors include the v0.7 vector extensions.  I have not confirmed this since a) all the documents are in Chinese, b) it requires an account to download, and c) I'm not interested in v0.7 anyways.

If you wish to disable auto-vectorization for any reason, please consider `-fno-vectorize` and `-fno-slp-vectorize`.  Vectorizer user documention can be found `here <https://llvm.org/docs/Vectorizers.html>`_.












-------------------------------------------------
SPEC 2017 Tuning Gotchas
-------------------------------------------------

This page is a summary of of known issues for getting a SPEC 2017 build
which is reasonably performant for purposes of performance analysis.  This
is not geared towards SPEC drag racing for peak score; it's goal is merely
to avoid encountering known issues and wasting time.  This page has a very
strong bias towards RISC-V specific and LLVM specific details, but might
have seeds of useful information for others as well.

Note that this builds on the standard SPEC public documentation.  There's
some duplication, but I don't repeat everything mentioned there.

.. contents::

gcc
---

Known to be extremely sensative to memcpy implementation.  If you're running
on a vector enabled system, make sure your glibc is patched to pickup
the vectorization changes for these routines.  Apparently
`these patches >https://patchwork.sourceware.org/project/glibc/list/?series=44338>_`
`*still* haven't made it upstream <https://patchwork.sourceware.org/project/glibc/patch/20250221095740.582183-3-daichengrong@iscas.ac.cn/#209206>_`
to glibc.

fotonik3d
---------

Avoid fast-math to get correct results, see e.g. https://gcc.gnu.org/bugzilla/show_bug.cgi?id=113570.
   
lbm
---

Due to a difference in clang and gcc set defaults for fp-contract, clang
looks much worse on this benchmark due to a lack of FMA formation.  See
https://discourse.llvm.org/t/impact-of-ffp-contract-defaults-on-benchmarking/87906
for further context.  Roughly a 7.3% dynamic icount difference for `rva22u64`.

namd
----

Same FMA issue as lbm, thought to a slightly lesser degree.  Roughly a 3.7%
dynamic icount impact for `rva22u64`.

povray
------

If you use -ffast-math, povray in both spec2006 and 2017 requires
`-fhonor-infinities` or `-ffinite-math-only` to produce correct results.

roms
----

Known to be sensative to vectorization of calls to "exp(double)", make sure
to build with recent SLEEF which supports a vector implementation of this
routine and thus allows the vectorizer to vectorize the key loop.

xalancbmk
---------

`-fwrapv-pointer` is required with recemt clang versions to avoid a newly
exposed UB, see https://github.com/llvm/llvm-test-suite/pull/236 for context.

May require `-fdelayed-template-parsing`. Maybe in spec2006 too.

Known to be sensative to allocator performance (i.e. use jemalloc).


Fortan/Flang
------------

The fortran runtime build does not support cross compilation, so you can't
link any fortran workload in a cross build.  You can hack the build system
a bit to get around this, but the resulting binaries play somewhat loose
with ABI contracts.

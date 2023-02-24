---------------------------
RISCV Attribute Validation
---------------------------

At the moment, this page is a collection of notes on the topic of attribute validation by the linker.  There's no real coherant message here - yet - it's more of a reference document to help organize my thoughts.

.. contents::

Compatibility
-------------

Since `87fdd7ac09b ("RISC-V: Stop reporting warnings for mismatched extension versions") <https://sourceware.org/git/?p=binutils-gdb.git;a=commitdiff;h=87fdd7ac09b>`_ which landed in 2.38, ld stopped trying to enforce any attribute compatibility.  Previous versions enforced the (at least) the following cases:

* Unrecognized extension name
* Mismatched extension version between object files

LD 2.38 is still pretty recent.  In particular, it has not yet (as of Feb 2023) made it into e.g. debian stable.

LLD historically did not enforce attribute consistency.  In `8a900f2438b4 ([ELF] Merge SHT_RISCV_ATTRIBUTES sections) <https://reviews.llvm.org/rG8a900f2438b4a167b98404565ad4da2645cc9330>`_ this was accidentally changed as part of a refacotring.  This is being treated as a regression (see `D144353 <https://reviews.llvm.org/D144353>`_), and will (hopefully!) not make it into a public release.

I have not investigated the status of `mold` or other linkers.

Previous Breakage
-----------------

Clang Built Linux (Multiple)
============================

Feb 2023 `breakage <https://github.com/ClangBuiltLinux/linux/issues/1808>`_ due to _zicsr_zifence with older LD.  Older versions of LD did not recognize these extension names and failed to link.  This case was a cross compatibility one; it was an LLVM toolchain which emitted the new extension.

Feb 2023 `breakage <https://github.com/ClangBuiltLinux/linux/issues/1777>`_ due to unrecognized I version with TOT LLD.  This is the LLD regression mentioned above, but is interesting to call out as it was a extension *version* which was unrecognized, not an extension *name*.

Feb 2023 breakage due to Zmmul implication.  I've been verbally told about this one, but can't find a citation.  My understanding is that older LD did not support Zmmul, but that newer (GNU?) toolchain did.  Thus linking within same toolchain family, but different versions broke.  Details here may be wrong.

Sept 2022 `breakage <https://github.com/ClangBuiltLinux/linux/issues/1714>`_ due to unrecognized `zicbom` extension with LD.  This is an another example of the toolchains evolving independently.  LLVM added zicbom and the version of LD used in a mixed environment did not support the extension.

More generally, the kconfig files are full of workarounds for related issues.


Use Cases
---------

Mixed Object Case (for e.g. environmental check dispatch)

Linking new object files with older linker

Cross toolchain linking (and thus version lock)

For both of prior two, sub-cases for unrecognized extension and version.

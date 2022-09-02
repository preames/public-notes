=============================
User Guide for RISC-V Target
=============================

.. contents::
   :local:

Introduction
============

The RISC-V target provides code generation for processors implementing
supported variations of the RISC-V specification.  It lives in the
``llvm/lib/Target/RISCV`` directory.

Base ISAs
=========

The specification defines four base instruction sets: RV32I, RV32E, RV64I,
and RV128I. Currently, LLVM fully supports RV32I, and RV64I.  RV32E is
supported by the assembly-based tools only.  RV128I is not supported.

To specify the target triple:

  .. table:: RISC-V Architectures

     ============ ==============================================================
     Architecture Description
     ============ ==============================================================
     ``riscv32``   RISC-V with XLEN=32 (i.e. RV32I or RV32E)
     ``riscv64``   RISC-V with XLEN=64 (i.e. RV64I)
     ============ ==============================================================

To select an E variant ISA (e.g. RV32E instead of RV32I), use the base
architecture string (e.g. ``riscv32``) with the extension ``e``.

.. _riscv-extensions:

Extensions
==========

The following table provides a status summary for extensions which have been
ratified and thus have finalized specifications.  When relevant, detailed notes
on support follow.

  .. table:: Ratified Extensions by Status

     =============  ========================
     Extension      Status
     =============  ========================
     ``A``          Supported
     ``C``          Supported
     ``D``          Supported
     ``F``          Supported
     ``M``          Supported
     ``V``          Supported
     ``Zba``        Supported
     ``Zbb``        Supported
     ``Zbc``        Supported
     ``Zbs``        Supported
     ``Zve32x``     Partially Supported
     ``Zve32f``     Partially Supported
     ``Zve64x``     Supported
     ``Zve64f``     Supported
     ``Zve64d``     Supported
     ``Zvl32b``     Partially Supported
     ``Zvl64b``     Supported
     ``Zvl128b``    Supported
     ``Zvl256b``    Supported
     ``Zvl512b``    Supported
     ``Zvl1024b``   Supported
     =============  ========================

``Zve32x``, ``Zve32f``, ``Zvl32b``
  LLVM currently assumes a minimum VLEN (vector register width) of 64 bits during compilation, and as a result ``Zve32x`` and ``Zve32f`` are supported only for VLEN>=64.  Assembly tools (e.g. assembler, dissambler, llvm-objdump, etc..) don't have this restriction.

Experimental Extensions
=======================

LLVM supports (to various degrees) a number of experimental extensions.  All experimental extensions have ``experimental-`` as a prefix.  There is explicitly no compatibility promised between versions of the toolchain, and regular users are strongly advised *not* to make use of experimental extensions before they reach ratification.

The primary goal of experimental support is to assist in the process of ratification by providing an existance proof of an implementation, and simplifying efforts to validate the value of a proposed extension against large code bases.  Experimental extensions are expected to either transiiton to ratified status, or be eventually removed.  The decision on whether to accept an experimental extension is currently done on an entirely case by case basis; if you want to propose one, attending the bi-weekly RISC-V sync-up call is strongly advised.

``experimental-zbe``, ``experimental-zbf``, ``experimental-zbm``, ``experimental-zbp``, ``experimental-zbr``, ``experimental-zbt``
  LLVM implements the `latest state of the bitmanip working branch <https://github.com/riscv/riscv-bitmanip/tree/main-history>`_, which is largely similiar to the 0.93 draft specification but with some instruction naming changes.  These are individual portions of the bitmanpip efforts which did *not* get ratified.  Given ratification for these sub-extensions appears stalled; they are a likely candidate for removal in the future.

``experimental-zca``
  LLVM implements the `0.70 draft specification <https://github.com/riscv/riscv-code-size-reduction/releases/tag/V0.70.1-TOOLCHAIN-DEV>`_.

``experimental-zihintntl``
  LLVM implements the 0.2 draft specification.

``experimental-zvfh``
  LLVM implements `this draft text <https://github.com/riscv/riscv-v-spec/pull/780>`_.


Specification Documents
=======================
For ratified specifications, please refer to the `official RISC-V International
page <https://riscv.org/technical/specifications/>`_.  Make sure to check the
`wiki for not yet integrated extensions
<https://wiki.riscv.org/display/HOME/Recently+Ratified+Extensions>`_.


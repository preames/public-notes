=============================
User Guide for RISCV-V Target
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

The specification defines three base instruction sets: RV32I, RV64I, and RV128I.
Currently, LLVM supports RV32I, and RV64I, but not RV128I.

To specify the target triple:

  .. table:: RISC-V Architectures

     ============ ==============================================================
     Architecture Description
     ============ ==============================================================
     ``riscv32``   RISC-V with ELEN=32
     ``riscv64``   RISC-V with ELEN=64
     ============ ==============================================================

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
     ``Q``          Supported
     ``V``          Supported
     ``Zicsr``      Supported
     ``Zifencei``   Supported
     ``Zba``        Supported
     ``Zbb``        Supported
     ``Zbc``        Supported
     ``Zbs``        Supported
     ``Zve32x``     Unsupported
     ``Zve32f``     Unsupported
     ``Zve64x``     Supported
     ``Zve64f``     Supported
     ``Zve64d``     Supported
     ``Zvl32b``     Unsupported
     ``Zvl64b``     Supported
     ``Zvl128b``    Supported
     ``Zvl256b``    Supported
     ``Zvl512b``    Supported
     ``Zvl1024b``   Supported
     =============  ========================

Zve32x, Zve32f, Zvl32b
  LLVM currently assumes a minimum VLEN (vector register width) of 64 bytes.

Specification Documents
=======================
For ratified specifications, please refer to the `official RISC-V International
page <https://riscv.org/technical/specifications/>`_.  Make sure to check the
`wiki for not yet integrated extensions
<https://wiki.riscv.org/display/HOME/Recently+Ratified+Extensions>`_.


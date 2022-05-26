---------------
Notes on RISCV
---------------

This document is a collection of notes on the RISC-V architecture.  This is mostly to serve as a quick reference for me, as finding some of this in the specs is a bit challenging.

.. contents::

VLEN >= 32 (always) and VLEN >= 128 (for V extension)
-----------------------------------------------------

VLEN is determined by the Zvl32b, Zvl64b, Zvl128b, etc. extensions. V implies Zvl128b. Zve64* implies Zvl64b. Zve32* implies Zvl32b. VLEN can never be less than 32 with the currently defined extensions.

Additional clarification here:

"Note: Explicit use of the Zvl32b extension string is not required for any standard vector extension as they all effectively mandate at least this minimum, but the string can be useful when stating hardware capabilities."

Reviewing 18.2 and 18.3 confirms that none of the proposed vector variants allow VLEN < 32.

As a result, VLENB >= 4 (always), and VLENB >= 16 (for V extension).

ELEN <= 64
----------

While room is left for future expansion in the vector spec, current ELEN values encodeable in VTYPE max out at 64 bits.

vsetivli can not always encode VLMAX
------------------------------------

The five bit immediate field in vsetivli can encode a maximum value of 31.  For VLEN > 32, this means that VLMAX can not be represented as a constant even if the exact VLEN is known at compile time.


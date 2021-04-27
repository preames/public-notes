.. header:: This is currently a DRAFT.  It may be arbitrarily wrong.  

-------------------------------------------------
Unintended Instructions on X86
-------------------------------------------------

This document is (intended to eventually be) an overview of techniques for handling unintended instructions,  My hope is that this will be helpful to others, but the primary goal is to help me organize my own thoughts and wrap my head around the literature on the topic.  I've been doing work on this topic for a client, and will be sending a related proposal to llvm-dev in the near future.  Once complete, this writeup will serve as background for that proposal.

.. contents::

Background
----------

X86 and X86-64 use a variable length instruction encoding.  There are some instructions which take just a byte, with others that can consume up to 15 bytes (the architectural limit).  This results in a situation where a valid instruction can start at any byte in the instruction stream.  The hardware does not enforce any alignment restrictions on branch targets, and thus each byte is potentially the target of some jump.

When describing X86 assembly, it is common to give a single instruction listing.  However, since decoding can start at any offset, there's effectively 15 parallel instruction streams possible through any particular offset in a string of executable bytes - one intended one, and 14 unintended misaligned streams.  Many times these parallel streams will be pure garbage, but unfortunately, not always.  It is entirely possible to have valid instructions occur in the misaligned streams.  These are termed "unintended instructions".

Consider as an example, the byte sequence represented by the hex string "89 50 04 d0 c3".  The following listing shows how this decodes with offset = 0, and offset = 1.  Note that both are valid (but quite different) instruction sequences.  For this particular example, those are the only interesting offsets as all others produce a sub-sequence of one of the two listed.  In general, we might have to look at 15 different offsets to see all possible instruction sequences from the same byte string.

:: 

  $ yaxdis  "895004d0c3"
  0x00000000: 895004        : mov [rax + 0x4], edx
  0x00000003: d0c3          : rol bl, 0x1
  $ yaxdis  "5004d0c3"
  0x00000000: 50            : push rax
  0x00000001: 04d0          : add al, -0x30
  0x00000003: c3            : ret

It is worth noting that since encodings are variable length, many unintended instruction sequences tend to eventually align to a boundary in the indended stream.  In practice, since X86 has many valid one byte instructions and one byte prefix bytes which are often not semantic, it is not uncommon to find a sequence of misaligned bytes which decode validly and yet end at a boundary in the original intended stream.  This results in a case where only the prefix of a sequence need be misaligned, and thus greatly increases the ease with which an attacker can exercise interesting control flow after executing their unintended instruction of interest.


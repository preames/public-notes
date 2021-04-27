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

One last bit of complexity comes up with the interpretation of bytes in the (misaligned) stream which don't decode to any known instruction.  Unfortunately, the key part of that staement is the word "known".  Unfortunately, it's been well established in the literature that just because a byte sequence isn't *documented* as having meaning does not mean it will not have *effects*.  It turns out that real processor behavior can and does differ from the documentation.  For instance:

* Various generations of intel processors differ in their handling of redundant or duplicate prefix bytes on instructions.  As a result, without knowing the exact processor executing the byte stream, it's impossible to accurately decode such a case.  For this particular case, thankfully all known behaviors either ignore the redundant prefixes or generate an illegal instruction fault.
* On certian VIA processors the byte sequence "0f3f" happens to transfer control to a highly privledged coprocessor despite not being a documented valid instruction.  While this is an extreme example, it's not unreasonable to expect processors to have unexpected behavior when executing garbage bytes.  This has in fact been reasonable well documented (e.g. sandshifter)

As a result, depending on our threat model, we may need to take great care when handling garbage bytes appearing in a misalgined stream.  At a minimum, an appropriate paraniod engineer is advised *not* to assume that executing garbage bytes will deterministic fault. Allowing for fallthrough is probably enough, but in principle there's nothing preventing those unknown effects from including control flow or other arbitrary processor side effects. In practice, all of the work I can find ignores this issue - which is probably fine in practice, but leaves at least a conceptual hole to be aware of.


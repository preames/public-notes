.. header:: This is currently a DRAFT.  It may be arbitrarily wrong.  

-------------------------------------------------
Unintended Instructions on X86
-------------------------------------------------

This document is (intended to eventually be) an overview of techniques for handling unintended instructions,  My hope is that this will be helpful to others, but the primary goal is to help me organize my own thoughts and wrap my head around the literature on the topic.  I've been doing work on this topic for a client, and will be sending a related proposal to llvm-dev in the near future.  Once complete, this writeup will serve as background for that proposal.

.. contents::

The Unintended Instruction Problem
----------------------------------

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

It is worth noting that since encodings are variable length, many unintended instruction sequences tend to eventually align to a boundary in the intended stream.  In practice, since X86 has many valid one byte instructions and one byte prefix bytes which are often not semantic, it is not uncommon to find a sequence of misaligned bytes which decode validly and yet end at a boundary in the original intended stream.  This results in a case where only the prefix of a sequence need be misaligned, and thus greatly increases the ease with which an attacker can exercise interesting control flow after executing their unintended instruction of interest.

One last bit of complexity comes up with the interpretation of bytes in the (misaligned) stream which don't decode to any known instruction.  Unfortunately, the key part of that statement is the word "known".  Unfortunately, it's been well established in the literature that just because a byte sequence isn't *documented* as having meaning does not mean it will not have *effects*.  It turns out that real processor behavior can and does differ from the documentation.  For instance:

* Various generations of Intel processors differ in their handling of redundant or duplicate prefix bytes on instructions.  As a result, without knowing the exact processor executing the byte stream, it's impossible to accurately decode such a case.  For this particular case, thankfully all known behaviors either ignore the redundant prefixes or generate an illegal instruction fault.
* On certain VIA processors the byte sequence "0f3f" happens to transfer control to a highly privileged co-processor despite not being a documented valid instruction.  While this is an extreme example, it's not unreasonable to expect processors to have unexpected behavior when executing garbage bytes.  This has in fact been reasonable well documented (e.g. sandshifter)

As a result, depending on our threat model, we may need to take great care when handling garbage bytes appearing in a misaligned stream.  At a minimum, an appropriate paranoid engineer is advised *not* to assume that executing garbage bytes will deterministic fault. Allowing for fallthrough is probably enough, but in principle there's nothing preventing those unknown effects from including control flow or other arbitrary processor side effects. In practice, all of the work I can find ignores this issue - which is probably fine in practice, but leaves at least a conceptual hole to be aware of.

Applications
------------

Before we dive into the meat of how we can avoid or render harmless unintended instructions, let's take a moment and cover a few use cases.  This is helpful in framing our thoughts if nothing else.

Reliable Disassembly
  For reverse engineering, debugging, and exploit analysis it is common to need to disassemble binaries.  For this use case, awareness of the existance of unintended instructions is the primary goal.  To my knowledge, there are no tools which do a good job of presenting the parallel execution streams.  Instead, the typical flow requires the human to iterate through attempting disassembly at different offsets.

Sandboxing
  In the realm of lightweight (i.e. user mode) sandboxing techniques, it's common to need to disallow particular instructions from occuring inside the sandboxed code.  Examples of opcodes which might be disallowed include: syscalls, user mode interrupts, pkey manipulation, segment state manipulation, or setting the direction flag.  We'll return to this application later in more depth.

Exploit Mitigation (e.g. defense in depth measures)
  For return oriented programming (ROP) style attacks, unintended instructions are frequently used to form "gadgets" which are in turned chained together into desired execution by the attacker.  One way to mitigate the damage of such attacks is to reduce the number of available gadgets.  I list this separately from sanboxing to emphasize that mitigation may take the form of a simple *reduction* in the number of available gadgets as opposed to an outright elimination thereof.  Beyond ret instructions, mitigation are often interested in reducing the number of, and maybe whitelisting occurrences of many of the same instruction families as come up when sandboxing.  (For the same reasons!)

Performance Optimization
  A particular form of sandboxing which is worth highlighting is to use sandboxing to optimize the execution of untrusted code.  The key difference with other sandboxing techniques is that a fallback safe execution mechanism is assumed to exist, but that mechanism implies overhead which can be avoided in the common case.  Examples might include optimized JNI dispatch for a JVM, a trap-and-step system (see below), or a user provided optimized binaries for a query engine.  The key difference in this use case is that failing to fully sandbox a piece of code is an acceptable (if not ideal) result as the slow path can always be taken.
  
I do want to highlight that the lines between these categories are somewhat blurry and subject to interpretation.  Is a system which attempts to sandbox user code but fails to account for the undocumented instruction issue (described above) or the spectre family of side channel attacks a sandbox or a mitigation?  I don't see much value in answering that question.  This writeup focuses on the commonalities between them, not the distinctions.  I view them more as a spectrum from weakest mitigation to strongest.  It is important to acknowledge that our perception of strength changes as new issues are discovered.  

Approaches
----------

There are three major family of approaches I'm aware of: trap-and-check, avoiding generation, and controlling reachability.  Let's go through each in turn.

Trap-and-check
  Works by identifying at load time all problematic byte sequences (whether intended or misaligned), and then using some combination of breakpoint-like mechanisms to trap on execution of code around the byte sequence of interest.  Mechanisms I'm aware of involve either hardware breakpoints, page protection tricks, or single stepping in an interrupt handler.  In all, some kind of fault handler is reasonable for insuring that unintended instructions aren't executed (e.g. the program counter never points to the stard of the unintended instruction and instead steps through the expected instruction stream.).
  The worst case performance of such systems tends to be poor (as trapping on the hot path can be extremely expensive), but perform at native speed when unintended instructions are not in the hot path.  They also tend to be operationally simpler as they don't require toolchain changes.

Controlling reachability
  Involves mechanisms to disallow edges in the (hardware) control flow graph.  The core idea is to prevent a control flow instruction from transfering control to the offset of the unintended instruction.  This ends up being a subset of control flow integrety to which there have been hundreds of approaches taken with different tradeoffs.  The core takeaway for me is that achieving both reasonable implementation complexity, full concurrency support, and low performance overhead is extremely challenging.  We'll come back in a moment to discussing two such approaches in a bit more depth.

Avoid generating unintended instructions
  Involves some adjustment to the toolchain used to generate the binary (and possibly to dynamic loaders) to avoid introducing unintended instructions into the binary to begin with.  This is the family of techniques we'll spent the most time discussing below.
  
I've listed these in the order of *seemingly* simplest to most complicated. Unfortunately, both of the former have hard to resolve challenges, so we'll end up spending most of our time talking about the third.

The challenge of the trap-and-check is that it is very hard to implement efficiently for concurrent programs with large number of unintended instructions.  Use of hardware breakpoints handles small numbers (e.g. < 4) unintended instructions well, which is enough for some use cases.  When the number of unintended instruction exceeds the number of debug registers, concurrency turns out to be a core challenge.  The critical race involves one thread unprotecting a page to allow it to make progress in single-step mode and another then accessing the same page thus bypassing the check.  You end up essentially needing to ensure that if any thread must single step through a page that all threads are either single stepping or stalled.  It is worth noting that a toolchain which avoiding emitting most (but not all) unintended instructions would pair very well with a trap-and-check fallback.

For the reachability based approaches, we'll briefly discuss two options.

NACL...

CET...

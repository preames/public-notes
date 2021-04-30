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


Rewrite Techniques
------------------

Instruction Boundary
====================

When the unintended instruction crosses the boundary between two or more intended instructions, the sequence can be broken by inserting padding bytes between the two intended instructions.  Depending on the instruction class being eliminated, redundant prefix bytes, a single byte ``nop`` instruction (``0x90``), or a semantic nop such as ``movl %eax, %eax``.  The selection of the padding is controlled by whether the bytes in the padding instruction can form a valid suffix (or prefix) with the preceding (following) bytes forming another problematic unintended instruction.  Depending on the class of problematic instruction, the selected padding sequence must differ.

From a performance perspective, prefix bytes are preferred over single byte nops which are preferred over other instructions.

Instruction Rewriting
=====================

This is by far the most complicated case.  I'll refer readers interested in the details to the Erim and G-Free papers, and restrict myself to some commentary here.

Completeness
++++++++++++

I find it difficult to convince myself of the completeness of either papers rewriting rules.  They seem to be heavily dependent on a complete taxonomy of the x86 decode rules, and prior experience makes me very hesitant about that.  As a particular example, neither paper seems to consider the case where a prefix byte forms part of an unintended instruction.  Particularly for VEX or EVEX, this seems to be a questionable assumption which would need justification.

Register Scavenging
+++++++++++++++++++

Each of the techniques mentioned sometimes need to reassign registers.  This is extremely hard to do in general as there may not be a register available for scavenging.  Both of the techniques which describe this use a post-compiler rewriting pass and fall back to stack spilling (which is ABI breaking!) in the worst case.

One point I don't see either paper make is that we can often scavenge a register by being willing to rematerialize a computation.  As an example, if the frame size is a constant but the code is preserving the frame pointer, RBP can be reliably scavenged and rematerialized after the local rewrite.  (Assuming the frame size doesn't itself form a problematic immediate at least.)

It's tempting to make this the compilers (specifically register allocation) responsibility, but since it requires knowledge of the encodings it would require breaking the compiler vs assembly abstraction.  We might be able to trick the compiler by adjusting instruction costing, but it's not clear this would behave well in the existing register allocation infrastructure.

Another approach would be to reserve a free register (i.e. guarantee scavenging could succeed), but that sounds pretty expensive performance wise.  Maybe we have the register allocator treat potentially problematic instructions as if they clobbered an extra register?  This would force a free register with at least much more localized damage.  It would require breaking the compiler/assembler abstraction a bit though.

Displacement Handling
+++++++++++++++++++++

As noted in the papers, we can insert nops to perturb displacement bytes which happen to encode unintended instructions.  Given little endian encoding, we can adjust the first byte by adding a single nop either before or after the containing intended instruction.  (If matching a set of adjacent encodings, we might need more than one.)

The other bytes are trickier.  Adjusting the other bytes with padding quickly gets really expensive code wise.  We have two main techniques open to us:

* If the unintended instruction ends at the end of the intended instruction's displacement field, and we can legally use a post-align and check pattern, we can simply add a post-check.
* If we can scavenge a register, we can use an LEA to form a portion of the address, and then use a smaller offset on the instruction.

Note that none of the three techniques mentioned can *always* produce a small rewrite.  The closest is the padding trick mentioned, but personally having to insert 10s of MBs of nop padding doesn't feel like a robust solution to me.

Alignment Sleds
===============

An alignment sled is a string of bytes which cause all possibly disassembly streams to align to a single stream.  A trivial instance of such a sequence is a single byte nop repeated 15 times.  The G-Free paper claims that a 9 byte sequence is sufficient, and smaller sequences are likely possible in manner specific cases (but not in general).

There are two forms of alignment sleds distinguished by their placement before or after the containing intended instruction.  (We'll assume here that an unintended instruction crossing multiple intended instructions has already been handled, so for this discussion we'll assume exactly one containing intended instruction.)  Each has restrictions on when it can be legally used.

Pre Align Sled
++++++++++++++

The idea behind an pre-align sled is a bit subtle.  The goal of a pre-align sled is to eliminate gadgets ending with the unintented instruction, not the removal of the unintended instruction itself.

Such a sled is placed *before* the containing instruction.  Note that the unintended instruction itself is not removed.  Instead, the alignment ensures that any misaligned sequence starting *before* the container intended instruction can't reach said instruction.  It does not prevent the attacker from branching directly to the start of the unintended instruction or to any byte between the start of the containing intended instruction and the start of the targeted unintended instruction.  

As a result, an pre alignment sled is only useful when a) the targeted unintended instruction can be allowed to execute (but not suffix a gadget), and b) the disassembly of all sequences starting with offsets after the beginning of the containing intended instruction are innocuous.  (i.e. do not form an interesting gadget)

The idea of pre alignment sleds was introduced (to me) in the G-Free paper.  I'll steal their example for illustration.

Given the intended instruction ``rolb %bl`` which encodes as ``d0 c3``, we have an unintended ret instruction in the second byte.  We can place an alignment sled before this (``90...90`` or ``nop;...;nop;``).  In this case, we have eliminated any gadget which exists before the unintended return, but we have *not* eliminated the actual return.


Post Alignment and Check
++++++++++++++++++++++++

This is essentially the inverse of the pre-alignment sled idea.  Rather than placing an alignment sled *before* a targeted instruction, we place it *after* the last containing intended instruction, and then follow the sled with an instruction specific check sequence.

Note that this requires the targeted unintended instruction to a) fallthrough (instead of transferring control), and b) have a side effect which can be deterministically detected.  It also requires the disassembly and inspection of the misaligned stream for the same conditions.  It would be problematic for a unintended instruction to be followed by an unintended branch before the alignment sled.

The length of the alignment sled can be reduced in many cases as we only need to unify the instruction stream containing the targeted unintended instruction and the intended instruction stream.  A particularly interesting special case is when the unintended instruction makes up a suffix of the intended one.  Such cases can commonly arise when unintended instructions are embedded in immediates or relative displacements.

As an example, consider the instruction ``or eax, 0x29ae0ffa`` which encodes as ``0dfa0fae29``.  The suffix of this encoding is ``0fae29`` which is ``xrstor [rcx]``.  If we're looking to use PKEY for sanboxing purposes, we can simply insert a check sequence to confirm the expected value is still in the pkru register at this point.

I haven't seen this approach used previously in the literature.  





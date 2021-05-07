.. header:: This is currently a DRAFT.  It may be arbitrarily wrong.  Feedback is very welcome.

-------------------------------------------------
Unintended Instructions on X86
-------------------------------------------------

This document is (intended to eventually be) an overview of techniques for handling unintended instructions,  My hope is that this will be helpful to others, but the primary goal is to help me organize my own thoughts and wrap my head around the literature on the topic.  I've been doing work on this topic for a client, and will doing some related work in upstream LLVM in the near future.  Once complete, this writeup will serve as background for that project.

.. contents::

The Unintended Instruction Problem
----------------------------------

X86 and X86-64 use a variable length instruction encoding.  There are some instructions which take just a byte, with others that can consume up to 15 bytes (the architectural limit).  This results in a situation where a valid instruction can start at any byte in the instruction stream.  The hardware does not enforce any alignment restrictions on branch targets, and thus each byte is potentially the target of some jump.

When describing X86 assembly, it is common to give a single instruction listing.  However, since decoding can start at any offset, there's effectively 15 parallel instruction streams possible through a string of executable bytes - one intended one, and 14 unintended misaligned streams.  Many times these parallel streams will be pure garbage, but unfortunately, not always.  It is entirely possible to have valid instructions occur in the misaligned streams.  These are termed "unintended instructions".

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
* On certain VIA processors the byte sequence ``0f3f`` will `transfer control to a highly privileged co-processor <https://i.blackhat.com/us-18/Thu-August-9/us-18-Domas-God-Mode-Unlocked-Hardware-Backdoors-In-x86-CPUs-wp.pdf>`_ despite not being a documented valid instruction.
* While the last case is an extreme example, it's not unreasonable to expect processors to have unexpected behavior when executing garbage bytes.  Processors are full of undocument instructions, as has been well documented by tools like `sandsifter <https://github.com/xoreaxeaxeax/sandsifter>`_.

As a result, depending on our threat model, we may need to take great care when handling garbage bytes appearing in a misaligned stream.  At a minimum, an appropriate paranoid engineer is advised *not* to assume that executing garbage bytes will deterministic fault. Allowing for fallthrough is probably enough, but in principle there's nothing preventing those unknown effects from including control flow or other arbitrary processor side effects.

Applications
------------

Before we dive into the meat of how we can avoid or render harmless unintended instructions, let's take a moment and cover a few use cases.  This is helpful in framing our thoughts if nothing else.

Reliable Disassembly
  For reverse engineering, debugging, and exploit analysis it is common to need to disassemble binaries.  For this use case, awareness of the existance of unintended instructions is the primary goal.  To my knowledge, there are no tools which do a good job of presenting the parallel execution streams.  Instead, the typical flow requires the human to iterate through attempting disassembly at different offsets.

Sandboxing
  In the realm of lightweight (i.e. user mode) sandboxing techniques, it's common to need to disallow particular instructions from occuring inside the sandboxed code.  Examples of opcodes which might be disallowed include: syscalls, user mode interrupts, pkey manipulation, segment state manipulation, or setting the direction flag.  We'll return to this application later in more depth.

Exploit Mitigation (e.g. defense in depth measures)
  For return oriented programming (ROP) style attacks, unintended instructions are frequently used to form "gadgets" which are in turned chained together into desired execution by the attacker.  One way to mitigate the damage of such attacks is to reduce the number of available gadgets.  I list this separately from sanboxing to emphasize that mitigation may take the form of a simple *reduction* in the number of available gadgets as opposed to an outright elimination thereof.  Beyond ret instructions, mitigation are often interested in reducing the number of, and maybe whitelisting occurrences of, many of the same instruction families as come up when sandboxing.  (For the same reasons!)

Performance Optimization
  A particular form of sandboxing which is worth highlighting is to use sandboxing to optimize the execution of untrusted code.  The key difference with other sandboxing techniques is that a fallback safe execution mechanism is assumed to exist, but that mechanism implies overhead which can be avoided in the common case.  Examples might include optimized JNI dispatch for a JVM, a trap-and-step system (see below), or user provided optimized binaries for a query engine.  The key difference in this use case is that failing to fully sandbox a piece of code is an acceptable (if not ideal) result as the slow path can always be taken.
  
I do want to highlight that the lines between these categories are somewhat blurry and subject to interpretation.  Is a system which attempts to sandbox user code but fails to account for the undocumented instruction issue (described above) or the spectre family of side channel attacks a sandbox or a mitigation?  I don't see much value in answering that question.  This writeup focuses on the commonalities between them, not the distinctions.  I view them more as a spectrum from weakest mitigation to strongest.  It is important to acknowledge that our perception of strength changes as new issues are discovered.  

Approaches
----------

There are three major family of approaches I'm aware of: trap-and-check, avoiding generation, and controlling reachability.  Let's go through each in turn.

Trap-and-check
  Works by identifying at load time all problematic byte sequences (whether intended or unintended), and then using some combination of breakpoint-like mechanisms to trap on execution of code around the byte sequence of interest.  Mechanisms I'm aware of involve either hardware breakpoints, page protection tricks, single stepping in an interrupt handler, or dynamic binary translation.  In all, some kind of fault handler is reasonable for insuring that unintended instructions aren't executed (e.g. the program counter never points to the start of the unintended instruction and instead steps through the expected instruction stream).
  The worst case performance of such systems tends to be poor (as trapping on the hot path can be extremely expensive), but perform at native speed when unintended instructions are not in the hot path.  They also tend to be operationally simpler as they don't require toolchain changes.

Controlling reachability
  Involves mechanisms to disallow edges in the (hardware) control flow graph.  The core idea is to prevent a control flow instruction from transfering control to the offset of the unintended instruction.  This ends up being a subset of control flow integrety to which there have been hundreds of approaches taken with different tradeoffs.  The core takeaway for me is that achieving both reasonable implementation complexity, full concurrency support, and low performance overhead is extremely challenging.  We'll come back in a moment to discussing two such approaches in a bit more depth.

Avoid generating unintended instructions
  Involves some adjustment to the toolchain used to generate the binary (and possibly to dynamic loaders) to avoid introducing unintended instructions into the binary to begin with.  This is the family of techniques we'll spent the most time discussing below.
  
I've listed these in the order of *seemingly* simplest to most complicated. Unfortunately, both of the former have hard to resolve challenges, so we'll end up spending most of our time talking about the third.

The challenge of the trap-and-check approach is that it is very hard to implement efficiently for concurrent programs with large number of unintended instructions.  Use of hardware breakpoints handles small numbers (e.g. < 4) of unintended instructions well - which is enough for some use cases.  When the number of unintended instruction exceeds the number of debug registers, concurrency turns out to be a core challenge.  The critical race involves one thread unprotecting a page to allow it to make progress in single-step mode and another then accessing the same page thus bypassing the check.  You end up essentially needing to ensure that if any thread must single step through a page that all threads are either single stepping or stalled.  It is worth noting that a toolchain which avoiding emitting most (but not all) unintended instructions would pair very well with a trap-and-check fallback.

The other major approach available is dynamic binary translation.  The complexity of building such a system is mostly out of scope for this document.  I will briefly mention that the need to intercept execution at every possible offset in a page does complicate hijacking significantly.  It can be done (e.g. by patching the source with ``int3``), but the complexity vs performance tradeoff is challenging.

For the reachability based approaches, we'll briefly discuss two options.

"Native client: A sandbox for portable, untrusted x86 native code" is one of most robust approaches I've seen.  NaCL prevents the execution of unintended instructions by ensuring that all branch targets are 32 byte aligned and that no instruction crosses a 32 byte boundary.  NaCL's instruction bundling support is already implemented in LLVM's assembler, and bundling has very low runtime cost.

The main challenge with NaCL is the performance overhead of return protection.  A return combines three operations: a load of the return address from the stack, an adjustment of the stack pointer, and an indirect branch.  The problem for efficient instrumentation is that in a concurrent environment, we need to instrument after the load, but before the branch.  This can't be done.  Instead, we have to use an alternate instruction sequence.  The primary effect of doing so is that return prediction is effectively disabled.  This is rather expensive - though I haven't been able to locate good numbers on exactly how much so.

Intel's upcoming Control Flow Enforcement Technology (CET) technology is highly relevant in this discussion.  CET contains two key pieces: a branch terminator instruction and a separate hardware managed return stack.  CET is certainly an interesting step forward, but it isn't a full solution.  ENDBR64 (the new branch terminator instruction) can itself occur in unintended instructions!  As a result, while CET does reduce the number of available gadgets greatly, it does not eliminate them entirely.  We'd still need some mechanism of handling unintended ENDBRs to be a complete sandboxing solution.

Towards the end of this document, we'll discuss CET in more detail.  The TLDR turns out to be that while CET is not complete, it is a rather good starting point for building a complete enough solution in practice.

Rewrite Techniques
------------------

In this section, we're discuss some of the tactics commonly used when rewriting assembly to avoid embedding unintended instructions.  These are described in terms of the assembly semantics, but this section is implementation neutral.  These could be implemented by a compiler, assembler, runtime binary rewritter, or even by a careful human in handwritten assembly.  Having a basic understanding of x86 instruction encoding is probably required for this to make sense.

Instruction Boundary
====================

When the unintended instruction crosses the boundary between two or more intended instructions, the sequence can be broken by inserting padding bytes between the two intended instructions.  Depending on the instruction class being eliminated, redundant prefix bytes, a single byte ``nop`` instruction (``0x90``), or a semantic nop such as ``movl %eax, %eax`` can be used.  The selection of the padding is controlled by whether the bytes in the padding instruction can form a valid suffix (or prefix) with the preceding (following) bytes forming another problematic unintended instruction.  Depending on the class of problematic instruction, the selected padding sequence must differ.

From a performance perspective, prefix bytes are preferred over single byte nops which are preferred over other instructions.

Instruction Rewriting
=====================

This is by far the most complicated case.  I'll refer readers interested in the details to the Erim and G-Free papers, and restrict myself to some commentary here.  This gets quite far into the weeds; most readers are probably best skimming through this unless implementing such a tool.

Completeness
++++++++++++

I find it difficult to convince myself of the completeness of either papers' rewriting rules.  They seem to be heavily dependent on a complete taxonomy of the x86 decode rules, and prior experience makes me very hesitant about that.  It is far to easy to think you have full coverage while actually missing important cases.

As a particular example, neither Erim or G-Free seems to consider the case where a prefix byte forms part of an unintended instruction.  From prior experience with x86, this seemed questionable.  A targetted fuzzer quickly found the example instruction ``vpalignr $239, (%rcx), %xmm0, %xmm8`` which encodes as ``c463790f01ef`` and thus embeds a ``wrpkru`` instruction in its suffix.  This example uses a three-byte VEX prefix to change the interpretation of the opcode field.

Register Scavenging
+++++++++++++++++++

Each of the techniques mentioned sometimes need to reassign registers.  This is extremely hard to do in general as there may not be a register available for scavenging.  Both of the techniques which describe this use a post-compiler rewriting pass and fall back to stack spilling (which is ABI breaking!) in the worst case.

One point I don't see either paper make is that we can often scavenge a register by being willing to rematerialize a computation.  As an example, if the frame size is a constant but the code is preserving the frame pointer, RBP can be reliably scavenged and rematerialized after the local rewrite.  (Assuming the frame size doesn't itself form a problematic immediate at least.)

It's tempting to make this the compilers (specifically register allocation) responsibility, but since it requires knowledge of the encodings it would require breaking the compiler vs assembly abstraction.  We might be able to trick the compiler by adjusting instruction costing, but it's not clear this would behave well in the existing register allocation infrastructure.

Another approach would be to reserve a free register (i.e. guarantee scavenging could succeed), but that sounds pretty expensive performance wise.  Maybe we have the register allocator treat potentially problematic instructions as if they clobbered an extra register?  This would force a free register with at least much more localized damage.  It would require breaking the compiler/assembler abstraction a bit though.

Relative Displacement Handling
++++++++++++++++++++++++++++++

Relative branches are a common important case since many of our unintended instructions happen to encode small integer constants, and short branches are quite common.  The techniques here can also be used for PC relative data loads (e.g. constant pools and such).

As noted in the papers, we can insert nops to perturb displacement bytes which happen to encode unintended instructions.  Given little endian encoding, we can adjust the final byte by adding a single nop either before or after the containing intended instruction.  (If matching a set of adjacent encodings, we might need more than one.)

The other bytes are trickier.  Adjusting the other bytes with padding quickly gets really expensive code wise.  We have two main techniques open to us:

* If the unintended instruction ends at the end of the intended instruction's displacement field, and we can legally use a post-align and check pattern, we can simply add a post-check.  (This overlaps with the nop case above, and is most useful when there are either other bytes which also need changed, or multiple problematic encodings for the last byte.)
* If we can scavenge a register, we can use an LEA to form a portion of the address, and then use a smaller offset on the instruction.

Note that none of the three techniques mentioned can *always* produce a small rewrite.  The closest is the padding trick mentioned, but personally having to insert 10s of MBs of nop padding doesn't feel like a robust solution to me.

Immediate Handling
++++++++++++++++++

For immediates, our main options are:

* Use the post-align-and-check trick if the immediate forms a suffix of the containing instruction.
* Scavenge a register, and use the register form of the instruction.  Immediate can be materialized into the register in as many steps as needed to avoid encoding an unintended instruction in the byte stream.
* For associative operations, we can split a single instruction into two each which performs part of the operation.  (e.g. ``or eax, -0x10fef100`` can become the sequence ``or eax, -0x10000000; or eax, -0x00fef100``)

Non-PC relative displacements are analogous, and can be handle similiarly.

Alignment Sleds
===============

An alignment sled is a string of bytes which cause all possibly disassembly streams to align to a single stream.  A trivial instance of such a sequence is a single byte nop repeated 15 times.  The G-Free paper claims that a 9 byte sequence is sufficient, and smaller sequences are likely possible in many specific cases (but not in general).  I have not checked their claim, and would want to fuzz extensively before trusting it.

There are two forms of alignment sleds distinguished by their placement before or after the containing intended instruction.  (We'll assume here that an unintended instruction crossing multiple intended instructions has already been handled, so for this discussion we'll assume exactly one containing intended instruction.)  Each has restrictions on when it can be legally used.

Pre Align Sled
++++++++++++++

The idea behind an pre-align sled is a bit subtle.  The goal of a pre-align sled is to eliminate gadgets ending with a particular unintented instruction, not the removal of the unintended instruction itself.

Such a sled is placed *before* the containing instruction.  Note that the unintended instruction itself is not removed.  Instead, the alignment ensures that any misaligned sequence starting *before* the container instruction can't reach said unintended instruction.  It does not prevent the attacker from branching directly to the start of the unintended instruction or to any byte between the start of the containing intended instruction and the start of the targeted unintended instruction.  

As a result, an pre alignment sled is only useful when a) the targeted unintended instruction can be allowed to execute (but not suffix a gadget), and b) the disassembly of all sequences starting with offsets after the beginning of the containing intended instruction are innocuous.  (i.e. do not form an interesting gadget)

The idea of pre alignment sleds was introduced (to me) in the G-Free paper.  I'll steal their example for illustration.

Given the intended instruction ``rolb %bl`` which encodes as ``d0 c3``, we have an unintended ret instruction in the second byte.  We can place an alignment sled before this (``90...90`` or ``nop;...;nop;``).  In this case, we have eliminated any gadget which exists before the unintended return, but we have *not* eliminated the actual return.


Post Alignment and Check
++++++++++++++++++++++++

This is essentially the inverse of the pre-alignment sled idea.  Rather than placing an alignment sled *before* a targeted instruction, we place it *after* the containing intended instruction, and then follow the sled with an instruction specific check sequence.

Note that this requires the targeted unintended instruction to a) fallthrough (instead of transferring control), and b) have a side effect which can be deterministically detected.  It also requires the disassembly and inspection of the misaligned stream for the same conditions.  It would be problematic for a unintended instruction to be followed by an unintended branch before the alignment sled.

The length of the alignment sled can be reduced in many cases as we only need to unify the instruction stream containing the targeted unintended instruction and the intended instruction stream.  A particularly interesting special case is when the unintended instruction makes up a suffix of the intended one.  Such cases can commonly arise when unintended instructions are embedded in immediates or relative displacements.

As an example, consider the instruction ``or eax, 0x29ae0ffa`` which encodes as ``0dfa0fae29``.  The suffix of this encoding is ``0fae29`` which is ``xrstor [rcx]``.  If we're looking to use PKEY for sanboxing purposes, we can simply insert a check sequence to confirm the expected value is still in the pkru register at this point.

I haven't seen this approach used previously in the literature.

Pre Setup/Post Checking
+++++++++++++++++++++++

A variant of the post align and check technique which can accelerate the check sequence is to scavenge a register whose value is consumed by the unintended instruction, pin it to a known value in the intended stream, and then check that value after the post-align sequence.  The idea is that the unintended instruction must fall down into that check, and if the value matches the expected value, we can reason about the path taken. Let me given a concrete example in terms of ``wrpkru`` to make this easier to follow.

Our intended instruction will be ``or eax, -0x10fef006`` which encodes ``wrpkru`` as it's suffix.  If we can scavenge either ECX or EDX, we can set them to a non-zero value.  ``wrkpru`` will fault if either register is anything other than zero.  After the intended instruction, we can check to see if our scavenged register is non-zero.  If it is, we know we'd only reached the check through the intended instruction stream.

Another way to achieve the same for ``wrpkru`` would be to write all ones to ``eax`` before the intended instruction.  If we reach the post-check with the value still in ``eax``, we know that either a) the intended path was followed, or b) the unintend path disabled access to all pkey regions.  (This doesn't work for our example because ``eax`` is not free.)

As you'll notice, the reasoning here is highly specific to particular unintended instruction being targetted for mitigation.

A deeper look at Intel CET
--------------------------

Does anyone actual have a link to a formal specification for CET or IBT?  I can find various blog posts and discussion, but all the links to specifications appear to be dead, and the ENDBR instruction is not yet documented in the most recent ISA document I can find.  

Intel CET consists of two parts: a hardware managed shadow stack for call return addresses, and a branch terminator instruction for indirect calls and branchs.  The later is called "Indirect Branch Tracking" (IBT).  At the moment, it's unclear to me whether IBT can be enabled independently of shadow stacks.  `This source <https://lists.llvm.org/pipermail/llvm-dev/2019-February/130538.html>`_ and `this <https://reviews.llvm.org/D79617>`_ seems to say "yes", but other sources seem to say "no".  The lack of a specification document is a tad annoying here.  If the answer turns out to be no, that would be a major limit on the value of CET.  Why?  Because shadow stacks are much harder to deploy that IBT is.

**Unintended ENDBRs**  As mentioned above, IBT is not a complete solution.  Unintended ENDBR instructions can still appear in the binary.  Interestingly, there `appears to be work going on <https://reviews.llvm.org/D88194>`_ in upstream LLVM to reduce the frequency of said unintended ENDBR instructions already.  (Start with that patch for the context, but see the submitted change - linked in the last comment - for the actual implementation.)

So let's take a look at the ease which which we can form unintended ENDBR instructions.  We'll use some targetting fuzzing to see what cases turn up, and combine that with information from the literature.

For the cross boundary case, fuzzing quickly finds a couple examples of instructions which encode a suffix for a byte stream containing ENBR64.  Examples include: ``bdf3f30f1e`` (``mov ebp, 0x1e0ff3f3; cli``) and ``1cf30f1efa`` (``sbb al, -0xd; nop edx``).  Interestingly, Section 3.2 of `"Security Analysis of Processor Instruction Set Architecture for Enforcing Control-Flow Integrity" <https://cseweb.ucsd.edu/~dstefan/cse227-spring20/papers/shanbhogue:cet.pdf>`_ (an Intel written academic paper on CET) claims the only suffix instructions possible on x86_64 are ``cli``, ``sti``, and ``nop edx``.  From some targeted fuzzing run for about 48 hours, this claim appears to be plausible.  ``cli`` and ``sti`` are used to manipulate the interrupt flag and are incredibly rare in practice.  ``nop edx`` isn't one of the Intel recommended nops for performance, and is thus likely to be a) uncommon, and b) easily replaceable.

For the embedded case (e.g. when a single containing instruction contains the unintended ENDBR), some quick fuzzing shows the immediate case appears to be the easiest to find.  The second and third most frequent appear to be displacements (e.g. ``vmaskmovpd ymm7, ymm11, [rdx - 0x5e1f00d]``) and field overlap with only some of the problematic bytes in the immediate field (e.g. ``xor ebx, -0x6505e1f1`` which encodes as ``81f30f1efa9a``).

* The full immediate case is handled by the changes `already landed in upstream LLVM <https://reviews.llvm.org/D89178>`_.
* The partial immediate case could be handled in an analogous manner by simple materializing the constant into a register and using the reg/reg form.  This wouldn't need the not operation, but would trigger on many more constants (since one byte is free).  In a quick skim of the fuzzer output, I have not seen a two byte overlap with an immediate, but I also haven't looked overly carefully just yet.  I also haven't yet looked closely to see if there's a patern to the fields being used to form the initial bytes of the ENDBR.
* For displacements in addressing, we could unfold the addressing mode.  As long as we did this before register allocation, register scavenging would not be a concern.  We have the same concerns about partial overlap as for immediates.
* For relative branches and calls, we'd need to teach the assembler how to pad.  Given ENDBR is a four byte instruction with a single fixed encoding, we should always be able to pad with a single byte.
* All of the above ignores problematic embeddings introduced by linker, and loader.  This may need explored further.

At least from this angle, the problem of unintended ENDBRs appears a lot more tractable than I'd initially suspected.  The bytes chosen appear to make the binary rewriting more-or-less straight forward.  It would also be valuable to survey a corpus of real binaries for naturally occurring ENDBRs.  This would give us a much better since of frequency of occurrence for each sub-case.
  
From a defense in depth perspective, it would also be interesting to know how many unintended no-track prefixed calls exist in the wild.  This would only be relevant once an initial compromise had occurred, but could have interesting implications for exploit difficulty.

**Linker and Loader** Presumably someone is working on preventing unintended ENDBRs being introduced during linking or dynamic loading.  I have not yet explored this, but do see signs that the deployment story has been considered.

**Deploying IBT** It's worth noting that a course grained CFI version can be constructed solely with IBT.  If each return instruction is replaced an indirect branch, and each call is followed by an ENDBR, we can use IBT alone to do both forward and backward edge CFI.  The catch is that this breaks the return prediction and is likely to negatively impact performance.  I mention this mostly because I expect Shadow Stacks to be slow to be fully deployed, and it seems useful to know there is an immediate state which is usable while waiting for Shadow Stacks to become widely available.

**Hardware Availability** CET was first announced in 2016, but hardware was quite delayed.  CET is supported by Intel's Tigerlake architecture which started shipping in Jan 2021.  I have been told that AMD's mobile 5000 parts include CET, but I can't find anything which spells out their broader support plans.

What would ideal hardware look like?
--------------------------------------------------

This section is a wish list.  If anyone at Intel or AMD happens to be reading, this is for you.  :)

If hardware/software co-design were practical in this space, I'd focus on enabling a NaCL like design.  I personally think the "aligned bundle of instructions" model is by far the most robust.  The challenge we have to address is the overhead of return checking.  With that in mind, my ideal hardware would be one of the following:

* A processor flag which caused the least significant N bits in a branch, call, or return destination to be ignored.  The processor could round to any fixed bit pattern (the obvious one is zero) for those bits.  This would allow near zero cost instruction bundling for reliable decode, and might also have other applications.  It would let you e.g. encode some metadata into the least significant bits of a function pointer.  Ideally, N would be runtime configurable, but I'd also be happy with any fixed value between 4 and 6.  (e.g. bundle sizes of 16 to 64 bytes).  Having this for all of branch, call, and return would be ideal, but the return is the critical one.  If needed, a new return instruction variant which ignored the bottom bits would be acceptable. Since this is wish list territory, I'll mention that a full word width "ignored branch bits" mask would be awesome for other purposes; it would e.g. allow encoding information into the high bits of function pointers in addition to the use described here.
* Alternatively, providing an instruction spelling which allows the address to be checked between the pop from the stack and the branch of a return would work.  The goal is to enable return prediction while allowing a separate instruction sequence to be used to check the return address before actually branching to it.  I can see several obvious ways to spell this; there may be others.  

  * First, we could have an instruction which pops a value from the stack with an explicit hint to the processor that that value is about to be branched to.  This could be followed by a custom check sequence and then a normal indirect branch.  
  * An alternate spelling of the last idea which would achieve the same effect would be a return instruction variant which accepted an target address (in register) to return to.  The key point is that the address branched to is expected to the be the same as pushed by the call instruction (in a nested manner.)  The return sequence would become ``pop; check_sequence; retindirect %rax;``.  This is very similiar to the check performed with shadow stack, but separates the shadow stack management (or other chosen check) from the semantics of the return instruction.
  * Another alternative would be to provide a "memory lock before return" instruction.  Single threaded code is easy to check by simply testing the value on the stack before a normal return sequence.  This isn't possible in multi threaded code due to race conditions.  This new instruction - which is similar in spirit to transaction memory or a linked load/store conditional - would "lock" the memory value read until the next return instruction.  It could be specified to either a) ignore concurrent writes, or b) fault on concurrent writes - either would be fine.

* Another possible approach would be to add a variant of ENDBR (the newly introduced branch terminator instruction from Intel CET) with an alignment restriction.  Such a ALIGNED_ENDBR would behave exactly like an ENDBR if the start (or end) of the instruction was aligned to a 32 byte boundary, but be guaranteed to generate a fault if not aligned.  Such an instruction would greatly simplify unintended instruction elimination as any unintended ALIGNED_ENDBR could be eliminated solely by padding between intended instructions.  
* If we're fixing CET, another wish list item would be to have a variant of ENDBR for return termination.  That is, instead of requiring the use of the separate hardware managed return stack, treat a return exactly like an indirect branch and require a branch terminator instruction.  (So, every call sequence would become ``callq foo; endret``.) An ENDRET could be used on any call within a single library, providing limited protection while supporting deployment independence.  (As with the ENDBR variant just discussed, the RETBR variant could have an alignment restriction.)

My personal preference would be the first variant; it seems simplest and (given what little I know about hardware) easiest to implement cheaply.  Any of these would be useful, and I suspect several could be repurposed for other uses as well.  These could combine in interesting ways as well.  For instance, if we had both an indirect return and the "return ignores low bits" flag, we could optimize checked return sequences for functions returning small integers.  

Appendex: The Mentioned Papers
------------------------------

I meantion several of the papers here above by their short name (e.g. "Erim", "G-Free", "Hodor").  This section gives an overview of each and the complete citation so that you can find them if desired.

"G-Free: defeating return-oriented programming through gadget-less binaries" describes a assembly rewriting scheme targetted at eliminating unintended return and call opcodes from a binary.  Their implementation was an assembly preprocessor.  This can be considered somewhat of an extreme case for instruction rewriting as their are multiple single byte return instructions, and multiple small (2-3 byte) call sequences.  This results in a focus on single instruction rewriting.

"Erim: Secure and efficient in-process isolation with memory protection keys" describes an approach for pkey related instructions using a post assembler binary rewriting step.  Several of the ideas discussed below in terms of rewriting strategies come from this paper.

"Hodor: Intra-Process Isolation for  High-Throughput Data Plane Libraries" is another take on a pkey based sandbox; this time using trap-and-check.  Worth noting is that Intel only supports 4 hardware debug registers, so programs which execute code with more than 4 unintended pkru instructions must take a much slower path.  


Interesting Partial Correctness Oracles - Primarily geared at using fuzzers to 
find compiler bugs, but also useful for "compile the world" style testing and 
general metric monitoring across a large corpus of applications.  

Assertion Builds - Duh.

Sanatizer Builds (ASAN, UBSAN, etc...) - Also duh, these days.

Hash Intermediate IRs to Detect Canonicalization Problems -- If the compiler has
passes which don't agree on the canonical form, this can result in alternation between
two IR states as the optimizer runs.  For any compiler with a serializeable IR,
this can be detected by logging the IR after each pass and looking for duplicates
via hashing.  (You could also use a more expensive comparison function such as llvm-diff,
but the extra time is probably not worth it.)

Does the resulting program run?  -- Useful way to detect many miscompiles even when
exact semantics of program aren't known.  Does require ability to generate fault free
(by construction) programs.  

Does the program terminate? -- Obvious problem is not knowing if the program is 
supposed to terminate.  In practice, can be really useful in finding algorithmic
cornercases in the compiler.  Filtering non-terminating (before timeout) examples
by whether there's a dominate stack trace for the whole execution and whether the
behavior is recent regression surfaces mostly real problems.  

Does the program produce the same result on two compilers or *two versions* of
the same compiler?  -- Very *very* effective at finding miscompile regressions
and subtle long standing miscompiles.  Requires either a) ability to generate
well defined source programs, b) a sanitizer like tool to make any program
well defined in practice, or c) a very good scoring/filtering mechanism.  
(a) or (b) are the strongly preferred approaches.

Maximum code expansion - A desirable property in a compiler is to not produce
output sizes which are exponential in the input size.  A fuzzer can be useful
way of finding such cornercases, though I'm not aware of anyone who has done
so to date.  


Performance fuzzing

One area which I think is very under-explored is using fuzzers to find regressions
in optimization effectiveness or missing optimizations in compilers.  If you have
a means of generating well defined programs and two compilers (or two compiler 
*versions*) you can simply run the same program compiled with both, and compare
the resulting execution times.

A couple of important points on making this work in practice.

1) Detecting a performance difference on a fuzzer test case will require *a lot*
of care about statistics.  This problem is absolutely begging for accidental
"p-hacking" and that needs to be a first class part of the design of any
practical system.

2) I'd expect such a system to have no trouble finding missed optimizations
and regressions.  (Compilers are full of them.)  I suspect the hard problem
would be prioritizing which ones matter, grouping them, and tying them to
other performance reports.  This problem is approachable for regressions, but
doing it for generic missed optimizations is not a problem I know how to approach.



Other random notes around fuzzing

Empirically, finding regressions requires about a million unique test executions.
No idea why, but most regressions fall out somewhere between a million and two
million unique tests executions.  (With a niave fuzzer, nothing fancy.  May differ
with better fuzzer technology.)  Assuming an average of 30 seconds per test (i.e.
a fairly slow fuzzer), that's only ~280 CPU hours at the high end.  (i.e. one 32 
core machine running for about 10 hours - or $5 at recent AWS spot prices.) At this
point, there is economically no excuse not to fuzz heavily.  

Empirically, finding long standing subtle miscompiles takes quite a bit longer.
One "interesting" (i.e. nasty, been latent for years, "how did we never see this?"
bug) seems to fall out about once per 150 million unique test inputs.  

The empirical statements above apply to fuzzing LLVM indirectly through Azul's
Falcon JIT using https://github.com/AzulSystems/JavaFuzzer.  Note that this
fuzzer is not coverage based and doesn't play any other "fun tricks".  



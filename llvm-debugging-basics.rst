-------------------------------------------------
LLVM Debugging Tricks
-------------------------------------------------

This page is a collection of basic tactics for debugging a problem with LLVM.  This is intended to serve as a reference document for new contributors.  At the moment, this is pretty bare bones; I'll expand on demand.  

.. contents::

Compiler Explorer (i.e. Godbolt)
--------------------------------

`https://godbolt.org/`_ is an incredibly useful tool for seeing how different compilers or compiler versions compile the same piece of code.  The ability to link to exactly what you're looking at and share it with collaborators is invaluable for asking and answering highly contextual questions.  


Assertion Builds
----------------

Before you do literally anything else, make sure that you have assertions enabled on your local build.  As a practical matter, I do not recommend the debug flavors of the builds, but Release with assertions enabled if very very worthwhile.  For context, an assertion enabled release build is around 8GB; last time I did a debug build, it was around 60GB.  

LLVM makes very heavy use of internal assertions, and they are generally excellent at helping to isolate a failure.  In particular, many things which appear as miscompiles in a release binary will exhibit as an assertion failure if assertions are enabled.

**Warning:** Few of the commands mentioned in this document will work without assertions enabled!

Capture IR before and after optimization
----------------------------------------

``-S -emit-llvm`` will cause clang to emit an .ll file.  This will contain the result of mid-level optimization, immediately before the invocation of the backend.

``-S -emit-llvm -disable-llvm-optzns`` will cause clang to emit an .ll file and *skip* optimization.  Note that this is often different than the result of ``-S -O0 emit-llvm`` as the later embeds ``optnone`` attributes in the IR.  


Capture IR before or after a pass
---------------------------------

``-mllvm -print-before=loop-vectorize -mllvm -print-module-scope`` will print the IR before each invocation of the pass "loop-vectorize".  (As it happens, there's only one of these in the standard pipeline.)  The resulting output will be valid IR (well, with a header you need to remove) which can be fed back to "opt" to reproduce a problem.

If you want to trace through execution, ``-mllvm -print-after-all`` can also be useful, but be warned, this is very very verbose.  Pipe it to a file, and search through it with a decent text editor is likely your best bet.

See what a pass is doing
------------------------

``-mllvm -debug-only=loop-vectorize`` turns on the internal debug tracing of the pass.  This can be very insightful when read in combination with the source code of the pass in question.

``-mllvm -pass-remarks=*`` turns on the pass remarks mechanism which is intended to be more user facing.  My experience is that these are generally not real useful, and that the filtering mechanism doesn't work well.  Mostly relevant when looking for missed optimizations.


opt and llc
------------

These tools are your friends.  You can pass IR to opt to exercise any mid-level optimization.  You can use llc to exercise the backend.

Many of the commands listed previously can be passed to opt or llc by simply omitting the ``-mllvm`` prefix.

llvm-reduce and bugpoint
------------------------

These tools provide a fully automated way to reduce an input IR program to the smallest program which triggers a failure.  Reducing crashes or assertion failures is pretty straight forward; reducing miscompiles is quite a bit trickier.

Alive2
------

Alive2 is a tool for formally reasoning about LLVM IR.  There is a web instance available at `https://alive2.llvm.org/ce/`_.  This is a great tool for quickly checking if an optimization you have in mind is correct.

You can also download and build alive2 yourself, and it has a lot of useful functionality for translation validation.  This can be very useful when tracking down a nasty miscompile, but is very much an advanced topic.  

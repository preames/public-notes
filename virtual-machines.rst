Safepoints and Checkpoints are Yield Points
--------------------------------------------

I recently read an `interesting survey of GC API design alternative available for Rust <https://manishearth.github.io/blog/2021/04/05/a-tour-of-safe-tracing-gc-designs-in-rust/>`_, and it included a comment about the duality of async and garbage collection safepoints which got me thinking.

Language runtimes are full of situations where one thread needs to ask another to perform some action on its behalf.  Consider the following examples:

* Assumption invalidation - When a speculative assumption has been violated, a runtime needs to evict all running threads from previously compiled code which makes the about to be invalidated assumption.  To do so, it must arrange for all other threads to remove the given piece of compiled code from it's execution stack.  
* Locking protocols - It is common to optimize the case where only a single thread is interacting with a locked object.  In order for another thread to interact with the lock, it may need the currently owning thread to perform a compensation action on it's default.
* Garbage collection - The garbage collector needs the running mutator threads to scan their stacks and report a list of garbage collected objects which are rooted by the given thread.
* Debuggers and profilers - Tools frequently need to stop a thread and ask it to report information about it's thread context.  Depending on the information required, this may be possible without (much) cooperation from the running thread, but the more involved the information, the more likely we need the queried thread to be in a known state or otherwise cooperate with the execution of the query.  

Interestingly, these are all forms of cooperative thread preemption (i.e. cooperative multi-threading).  The currently running task is interrupted, another task is scheduled, and then the original task is rescheduled once the interrupting task is complete.  (To avoid confusion, let's be explicit about the fact that it's semantically the *abstract machine thread* being interrupted and resumed.  The physical execution execution may look quite different once abstract machine execution resumes for the interrupted thread.)

Beyond these preemption examples, there are also a number of cases where a single thread needs to transition from one physical execution context to another.  Conceptually, these transitions don't change the abstract machine state of the running thread, but we can consider them premption points as well by modeling the transition code which switches from one physical execution context to another as being another conceptual thread.  

Consider the "on stack replacement" and "uncommon trap" or "side exit" transitions.  The former transitions a piece of code from running an interpreter to a compiled piece of code, the later does the inverse.  There's usually a non-trivial amount of VM code which runs between the two pieces of abstract machine execution to do e.g. argument marshalling and frame setup.  We can consider there to be two conceptual threads: the abstract machine thread, and the "transition thread" which is trying to transition the code from one mode of execution to another.  The abstract machine thread reaches a logical premption point, transitions control to the transition thread, and then the transition thread returns control to the abstract machine thread (but running in another physical tier of exeuction.)

It is worth highlighting that while this is cooperative premption, it is not *generalized* cooperative premption.  That is, the code being transitions to at a premption point is not arbitrary.  In fact, there are usually very strong semantic restrictions on what it can do.  This restricted semantics allows the generated code from an optimized compiler to be optimized around these potential premption points in interesting ways.

It is worth noting that (at least in theory) the abstract machine thread may have different sets of premption points for each class of prempting thread.  (Said differently, maybe not all of your lock protocol premption points allow general deoptimization, or maybe your GC safepoints don't allow lock manipulation.)  This is quite difficult to take advantage of in practice - mostly because maintaining any form of timeliness guarantee gets complicated if you have unbounded prempting tasks and don't have the ability to prempt them in turn - but at least in theory the flexibility exists.

This observation raises some interesting possibilities for implementing safepoints and checkpoints in a compiler.  There's a lot of work on compiling continuations and generators, I wonder if anyone has explored what falls out if we view a safepoint as just another form of yield point?  Thinking through how you might level CPS style optimization tricks in such a model would be quite interesting.  (This may have already been explored in the academic literature, CPS compilation isn't an area I follow closely.)  


Tier transitions as tail calls
-------------------------------

When transitioning from one tier of execution to another, we need to replace on executing frame with another.  For example, when deoptimzing from compiled code to the interpreter you need to replace the frame of the executing function with an interpreter frame and setup the interpreter state so that execution of the abstract machine can resume in the same place.  

(For purpose of this discussion, we're only considering the case where the frame being replaced is the last one on the stack.  The general case can be handled in multiple ways, but is beyond the scope of this note.)

Worth noting is that this frame replacement is simply a form of guaranteed tail call.  The source frame is essentially making a tail call to another function with the abstract machine state as arguments.  (For clarity, the functions here are *physical* functions, not functions in the abstract machine language.)  This observation is mostly useful from a design for testability perspective and, potentially, code reuse.  If the abstract machine includes tail calls (either guaranteed or optional), the same logic can be used to implement both.  

You could generate a unique runtime stub per call site layout and abstract machine state signature pair.  If you're using a compiler toolchain which supports guaranteed tail calls - like LLVM - generating such a stub is fairly trivial.  (Note: Historically, many VMs hand roled assembly for such cases.  Don't do this!)

If you start down this path, you frequently find you have a tradeoff to make between number of stubs (e.g. cold code size), allowed call site layouts (e.g. performance of compiled code), and distinct abstract machine layouts (e.g. your interpreter and abstract language designs).  A common technique which is used to side step this tradeoff is to allow the compiler to describe the callsite layout (e.g. which arguments are where) in a side table which is intepreted at runtime as opposed to a function signature intepreted at stub generation time.

Let's explore what that looks like.  

Information about the values making up the abstract machine state is recorded in a side table.  The key bit is that minimal constraints are placed on where the values are; as long as the side table can describe it, that's a valid placement.  This may sound analogous to debug information, but there's an important semantic distinction.  Unlike debug info which often has a "best effort" semantic, this is *required* to be preserved for correctness.

At runtime, there's a piece of code which copies values from wherever they might have been in executing code, and the desired target location.  This often ends up taking the form of a small interpreter for the domain specific language (DSL) the side table can describe.

In LLVM, the information about the callsite is represented via the "deopt" bundle on the call.  During lowering, values in this bundle are allowed to be assigned freely provided the location is expressible in stackmap section which is generated into the object file.  LLVM does not provide a runtime mechanism for interpreting a stackmap section, that's left as an exercise for the caller.  Note that the name "stackmap" comes from the fact that garbage collection is stored in the same table.  This is an artifact of the implementation.  

A couple of observations on the scheme above.

* You'll note that we're replacing a stub with assembly optimized for a *particular* source/target layout pair with a generic intepreter.  This is obviously slower.  That's okay for our use case as deoptimization is assumed to be rare.  As a result, smaller code size is worth the potential slowdown on the deoptimization path.
* There's a data size impact for the side table.  In general, these tend to be highly compressible, and are rarely accessed.  Given that, it's common to use custom binary formats which fit the details of the host virtual machine.  There's some interesting possibilities for using generic compressio techniques, but to my knowledge, this has not been explored.
* There's a design space worth exploring around the expressibility of the side table.  The more general such a table is - and thus the more complicated our runtime intepreter is - the less impact we have on the code layout for our compiled code.  In practice, representing constants, registers, and stack locations appears to get most of the low hanging fruit, but this could in principle be pushed quite far.
* It's worth noting that this is a *generic* mechanism to perform *any* (possibly tail) call.  I'm not aware of this being used outside of the virtual machine implementations, but in theory, a suficiently advanced compiler could use this for any sufficiently cold call site.  
* This may go without saying, but it's important to have a mechanism for forcing deoptimation from your source language for testing purposes.  (e.g. Being able to express the "deopt-here!" command in a test)  Corner cases in deoptimization mechanisms tend to be hard to debug since they are by definition rare.  You really want both a way to write test cases, and (ideally) fuzz.


-------------------------------------------------
Pointer Provenance in LLVM
-------------------------------------------------

**THIS IS AN IN PROGRESS DOCUMENT.  It hasn't yet been "published".  At the moment, this is KNOWN to not work.**

This write up is an attempt for me to wrap my head around the recent byte type discussion on llvm-dev.

.. contents::

I'm going to start by stating a few critical tidbits as I think there's been some confusion about this in the discussion thread.

Memory is not typed (well mostly)
---------------------------------

Today, LLVM's memory is not typed.  You can store one type, and load back the same bits with another type.  You can used mismatched load and store widths.

However, this is *not* the same as saying memory holds only the raw bits of the value.  There are a couple of cornercases worth talking through.  

First, we model uninitialized memory as containing a special ``undef`` value.  This value is a special placeholder which allows the compiler to chose any value it wishes independently for each use.

Second, we allow ``poison`` to propogate through memory.  Poison is used to model the result of an undefined operation (e.g. an add which was asserted not to overflow, but did in fact overflow) which has not yet reached a point which triggers undefined behavior.  The definition of poison carefully balances allowing operations to be hoisted with complexity of semantics.  We've only recently gotten ``poison`` into a somewhat solid shape.

The key bit about both is that the rules for poison and undef propogation and the dynamic semantics of LLVM IR instructions with regards to each are chosen carefully such that "forgetting" memory contains ``undef`` or ``poison`` is entirely correct.  Or to say it differently, converting (intentionally or unintentionally) either to a specific concrete value is a refining transformation.

Aside: For garbage collection, we added the concept of a non-integral pointer type.  The original intent was *not* to require typed memory, but in practice, we have had to essentially assume this.  For a collector which needs to instrument pointer loads (but *not* integer loads), having the optimizer break memory typing.  If anything, this provides indirect evidence that memory is not typed, as otherwise non-integral pointers would have never been needed.

Aliasing vs Pointer Equality
----------------------------

The C/C++ rules for what is legal with an out of bounds pointer are complicated.  This is relevant because LLVM IR needs to correctly model the semantics of these languages.  Note that it does *not* mean that LLVM's semantics must exactly follow the C/C++ semantics, merely that there must be a reasonable translation from one to the other.

The key detail which is relevant here is that pointer *values* can be legally compared and have well defined semantics while *accessing the memory pointed to* may be fully undefined.  

This comes up in the context of alias analysis because it's possible to have two pointers which are equal, but don't alias.  The classic example would be:

.. code::

  %v1 = malloc(8)
  %v2 = realloc(%v1, 8)
  %v1 and %v2 *may* be equal here, but are guaranteed no-alias.  

Aside: If the runtime allows multi-mapping of memory pages, it's also possible to have two pointers which are inequal, but must alias.  This isn't well modeled today in LLVM, and is definitely out of scope for this discussion.

Memory Objects
--------------

The LLVM memory model consists of indivially memory allocations which are (conceptually) infinitely far apart in memory.  In an actual execution environment, allocations might be near each other.  To reconcile this, it's important to note that comparing or subtracting two pointers from different allocations results in an undefined (i.e. ``poison``) result.  

So what?
---------

My understanding of the current pointer providence rules is the following:

* A pointer is (conceptually) derived from some particular memory object.
* We may or may not actually be able to determine which object that is.  Essentially this means there is an ``any`` state possible for pointer provenance.  
* The optimizer is free to infer providance where it can.  BasicAA for instance, is essentially a complicated providance inference engine.

There's a key implication of the second bullet.  Provenance is propogated through memory for pointer values.  We may not be able to determine it statically (or dynamically), but conceptually it exists.

This implies there are some corner cases we have to consider around "incorrectly" typed loads, and overlapping memory accesses.  At the moment, I don't see a reason why we can simply define the providance of any pointer load which doesn't exactly match a previous pointer store as being ``any``.  We do need to allow refining transformations which expose providance information (e.g. converting a integer store to a pointer one if the value being stored is a cast pointer), but I don't see that as being particular problematic.

Let me try stating that again, this time a bit more formally.

We're going to define a dynamic (e.g. execution or small step operational) semantics for pointer providance.  Every byte of a value will be mapped to some memory object or one of two special marker value ``poison`` or ``undef``.  Note that this is *every* value, not just *pointer values*.   

Allocations define a new symbolic memory object.  GetElementPtrs generally propogate their base pointer's provinance to their result, but see the rule below for mismatched providence.

Storing a pointer to memory conceptually creates an entry in a parallel memory which maps those bytes to the corresponding memory object.  Every time memory is stored over, that map is updated.  Additionally, the side memory remembers the bounds of the last store which touches each byte in memory.

Loading a pointer reads the last written providance associated with the address.  If the bytes read were last written by two different stores, the resulting providance is ``poison``.

Casting a pointer to an integer does *not* strip providance.  As a result, round tripping a pointer through an integer to pointer cast and back is a nop.  This is critical to keep the correspondance with the memory semantics.

Integer constants are considered to have the providance of the memory object which happens to be at that address at runtime, or the special value ``undef`` if there is not such memory object.  

Any operation (gep, or integer math) which consumes operands of two distinct providances returns a result with the providance``poison`` with the caveat that an ``undef`` providance can take on the value of any memory object chosen by the optimizer.  (This is analogous to ``undef`` semantics on concrete values, just extended to the providance type.)  Note that the result is *not* the ``poison`` value, it as a value with ``poison`` providance.  

Memory operations with a memory operand with ``poison`` providence are undefined.  Comparison instructions with a pointer operand with ``poison`` providance return the value ``poison``. 

Now, let's extend that to a static semantic.  The key thing we have to add is the marker value ``any`` as a possible providance.  ``any`` means simply that we don't (yet) know what the providance as, and must be conservative in our treatment.

As is normal, the optimizer is free to implement refining transformations which make the program less undefined.  As a result, memory forwarding, CSE, etc.. all remain legal.

**BUG**: CSE of two integer values with difference providance seems to not work.



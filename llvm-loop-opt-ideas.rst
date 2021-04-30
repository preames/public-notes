.. header:: This is a collection of examples and ideas for potential loop opts in LLVM.  This is mostly a dumping ground for things I've written up once and want to be able to reuse later.

-------------------------------------------------
LLVM Loop Opt Ideas
-------------------------------------------------

.. contents::

Multiple Exit Loops
-------------------

See my talk on the subject from the LLVM Developers Conference in 2020.  

See also `my proposal <https://lists.llvm.org/pipermail/llvm-dev/2019-September/134998.html>`_ to llvm-dev from back in 2019 on extending the loop vectorizer to support multiple exit loops.  I have some patches which support the most basic cases.  The last one was reverted due to an exposed bug, and I haven't had time to isolate it just yet.

Note that when I talk about multiple exits, I am generally only talking about the case where each exit dominates the latch block of the loop.  The case where an exit is conditional and doesn't dominate the latch is much rarer and harder to easily handle.


Internal Control Flow 
---------------------
(Specifically, the subset where where Iteration Set Splitting is possible.)

A couple of general comments.


I really don't think that extending IRCE is the right path
            forward here. IRCE has some serious design defects, and I'm
            honestly quite nervous about it's correctness. I think that
            iteration set splitting (the basic transform IRCE uses) is
            absolutely something we should implement for the main
            pipeline, but I'd approach it as building new infrastructure
            to replace IRCE, not as getting IRCE on by default. In
            particular, I suspect the value comes primarily from a cost
            model driven approach to splitting, not IRCE's unconditional
            one.


          Second, I advise being very cautious about going directly
            for the general case here. The general case for this is
            *really really hard*. If it wasn't, we'd already have robust
            solutions. If you can describe your motivating examples in a
            bit more depth (maybe offline), we can see if we can find a
            specific sub-case which is both tractable and profitable.


In this example, forming the full pre/main/post loop structure of IRCE is overkill.  Instead, we could simply restrict the loop bounds in the following manner:

.. code::

loop.ph:
  ;; Warning: psuedo code, might have edge conditions wrong
  %c = icmp sgt %iv, %n
  %min = umax(%n, %a)
  br i1 %c, label %exit, label %loop.ph

loop.ph.split:
  br label %loop

loop:
  %iv = phi i64 [ %inc, %loop ], [ 1, %loop.ph ]
  %src.arrayidx = getelementptr inbounds i64, i64* %src, i64 %iv 
  %val = load i64, i64* %src.arrayidx
  %dst.arrayidx = getelementptr inbounds i64, i64* %dst, i64 %iv 
  store i64 %val, i64* %dst.arrayidx
  %inc = add nuw nsw i64 %iv, 1
  %cond = icmp eq i64 %inc, %min
  br i1 %cond, label %exit, label %loop

exit:
  ret void
}

I'm not quite sure what to call this transform, but it's not IRCE.  If this example is actually general enough to cover your use cases, it's going to be a lot easier to judge profitability on than the general form of iteration set splitting.  

Another way to frame this special case might be to recognize the conditional block can be inverted into an early exit.  (Reasoning: %iv is strictly increasing, condition is monotonic, path if not taken has no observable effect)  Consider:

.. code::

loop.ph:
  br label %loop

loop:
  %iv = phi i64 [ %inc, %for.inc ], [ 1, %loop.ph ]
  %cmp = icmp sge i64 %iv, %a
  br i1 %cmp, label %exit, label %for.inc

for.inc:
  %src.arrayidx = getelementptr inbounds i64, i64* %src, i64 %iv 
  %val = load i64, i64* %src.arrayidx
  %dst.arrayidx = getelementptr inbounds i64, i64* %dst, i64 %iv 
  store i64 %val, i64* %dst.arrayidx
  %inc = add nuw nsw i64 %iv, 1
  %cond = icmp eq i64 %inc, %n
  br i1 %cond, label %exit, label %loop

exit:
  ret void
}


Once that's done, the multiple exit vectorization work should vectorize this loop. Thinking about it, I really like this variant.  

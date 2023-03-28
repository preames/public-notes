--------------------------
LLVM Shuffles by Example
-------------------------

This document is an overview of the various common shuffle operations in LLVM's backend lowering.  I'm currently working on improving the RISC-V backends handling of fixed length shuffles, and this is being written to help me organize my thoughts.

.. contents::

Broadcast Variants
------------------

A general broadcast takes a single vector element (any vector element), and repeats it across all lanes of the containing vector.  Particularly useful forms of broadcast involve broadcasting the element at lane 0, and broadcasting a scalar element to all lanes of the vector type.  In code, we often comingle the naming of these, so you sometimes have to pay attention to figure out which variant is being discussed.

Examples:

.. code::

   ;; Broadcast lane 0 to all lanes
   ;; ------------------------------

   ;; Fixed vector
   shufflevector <4 x i32> %vec, <4 x i32> undef, <4 x i32> zeroinitializer

   ;; Scalable vector
   shufflevector <vscale x 1 x i32> %vec, <vscale x 1 x i32> undef, <vscale x 1 x i32> zeroinitializer

   ;; Broadcast a scalar to all lanes
   ;; -------------------------------

   ;; Fixed vector
   %vec = insertelement <4 x i32>, i32 %elem, i64 0
   shufflevector <4 x i32> %vec, <4 x i32> undef, <4 x i32> zeroinitializer

   ;; Scalable vector
   %vec = insertelement <4 x i32>, i32 %elem, i64 0
   shufflevector <vscale x 1 x i32> %vec, <vscale x 1 x i32> undef, <vscale x 1 x i32> zeroinitializer   

   ;; Broadcast the value in lane 1 to all lanes
   ---------------------------------------------

   ;; Fixed vector
   shufflevector <4 x i32> %vec, <4 x i32> undef, <4 x i32> <i32 1, i32 1, i32 1, i32 1>

   ;; Scalable vector
   ;; Not cleanly representable


In TargetTransformInfo, `SK_Broadcast` specifically refers to a lane 0 broadcast (possibly of a scalar).  The generic any-lane broadcast becomes a `SK_PermuteSingleSrc`.


Single Source Permutes
----------------------

A single source permute is a shuffle where all output lanes come from one of the two input vectors.  IT represents a permutation of exactly one of the input vectors.  A permute does not change the length of the vector.

In TargetTransformInfo, `PermuteSingleSrc` models this case. There are multple sub-categories within single source permutes where better lowerings are available.  See also interleave, deinterleave, select, broadcast, and reverse.


Two Source Permutes
-------------------

A two source permute is a shuffle where the output length is equal to the length of each of the input vectors.  Conceptually, there's two (equivalent) common mental models.  The first is that we perform a single source permute on the result of concatenating the two source vectors and then extract the leading sub-vector.  The second is that we perform one permute on each source vector, and then merge the results with a vector select.


In TargetTransformInfo, `SK_PermuteTwoSrc` models this case.  It is the fallback for when nothing more specific can be identified.


Others (Updates Pending)
-------------------------

.. code::

    SK_Reverse,          ///< Reverse the order of the vector.
    SK_Select,           ///< Selects elements from the corresponding lane of
                         ///< either source operand. This is equivalent to a
                         ///< vector select with a constant condition operand.
    SK_Transpose,        ///< Transpose two vectors.
    SK_InsertSubvector,  ///< InsertSubvector. Index indicates start offset.
    SK_ExtractSubvector, ///< ExtractSubvector Index indicates start offset.
    SK_Splice            ///< Concatenates elements from the first input vector
                         ///< with elements of the second input vector. Returning
                         ///< a vector of the same type as the input vectors.
                         ///< Index indicates start offset in first input vector.

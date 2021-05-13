-------------------------------------------------
LLVM Norms, Terminology, and Expecations
-------------------------------------------------


This page is a collection of things I find myself repeatedly needing to explain to new developers.  This is not official project documentation; it is my take on each issue.  Most of this is likely to agree broadly with what other long term contributors might say, but details in perspective may differ.

Let me start by introducing myself in case you're not already familiar with my work in the project.  I am a long standing contributor to the LLVM project.  I've contributed heavily to the mid level optimizer, and to a lesser extend parts of the X86 backedge.  I was the technical lead for the Falcon JIT - an LLVM based just in time compiler for Java bytecode.  I've managed a team of LLVM contributors, and been responsible for maintaining a long live downstream distribution of LLVM.  As such, I have a fairly broad perspective on what it takes to participate in the upstream community successfully, while still shipping downstream product.

.. contents::

What does LGTM mean?
--------------------

"LGTM" literally means "looks good to me", but there's a bunch more cultural context behind it.  LLVM requires pre-commit review for most changes.  For new contributors, *all* changes will require precommit review.  Having an established contributor LGTM a change is the gate which had to be cleared before a change can land.

While most reviews these days use phabricator, we're not always good about marking reviews approved through the UI.  A textual LGTM is what matters, not whether the review has been approved in the UI.  

Let me emphasize that LLVM is a single approval culture.  This means that once a knowledgeable reviewer has approved a patch, you do not need to wait for furthur reviewer approval.  You do need to use reasonable judgement here though.  If another reviewer has raised concerns, you probably want to wait until they've had a chance to reply to any changes before landing.  

One point which confuses a bunch of new contributors is that LLVM reviewers **expect that you have commit rights**.  Unless you **explicitly ask** someone to land your change on your behalf, reviewers will assume that you will do so after approval.  This comes from the fact that LLVM hands out commit rights much more freely than other open source projects.

LGTMs w/Conditions
------------------

It's not uncommon to see phrasings such as "LGTM w/comments addressed" or "LGTM w/minor comments".  What this means is that once you've addressed the issues identified *as suggested by the reviewer*, you can consider the patch to have received an LGTM without the need for further review.

This is frequently used by reviewers when the remaining issues with the patch are considered minor and straight forward.  If you as an author disagree with how any issue should be handled (e.g. a comment needs discussion), be aware that you don't have an LGTM without further discussion and an explicit re-LGTM by that reviewer (or someone else).

If the difference in approach is minor, I strongly suggest taking the reviewer's suggestion, landing your patch, and then posting a follow up patch to switch to your preferred approach.  This will let all parties make progress, and avoids back and forth on already accepted reviews which has a tendancy to get lost.  

Another form of conditional LGTM which comes up regularly is the "LGTM, but wait for @name" or "LGTM, but wait a couple of days in case @name has further comments".  These two are interesting precisely because they are *different*, and that subtly is often lost on non-native speakers.  For the first, the reviewer is explicitly asking for a second LGTM.  As such, our general "single accept" policy does not apply, and this review is blocked on a second accept by @name.  The second is merely instructing you to wait a couple of days before landing so that @name has a chance to chime in if desired.  The former blocks commit; the latter does not.  

What are "commit rights"?
--------------------------

LLVM grants commit rights much more freely than most other open source projects.  However, that's because the implied expectationss are very different.  In LLVM, having commit rights simply means that you are trusted to take the mechanical action of rebasing and landing an approved patch, and then respond promptly to post commit review.  It **does not** change any expectation around precommit review, or imply anything beyond a very basic level of trust.  

Can I commit my change without review?
--------------------------------------

As a general rule, unless you have been told otherwise, no.  New contributors, in particular, should *never* commit a change without review.

Beyond that initial state, we have in practice three levels of pre-commit rights.  

First, you'll pretty quickly be asked by reviewers to "pre-commit this test", or "pre-commit this NFC".  That means that you can separate out a change which does that (and only that), and submit it without further review.  A key point is that this change *was reviewed* in the original review thread.  The trust being shown is minor, and mostly mechanical.

Second, once you've been around for a while and have a sense of normal review flow, you'll reach the point where you have a good sense for what you'll be asked to pre-commit to reduce patch sizes during review.  Once you hit that point, checking in tests and NFCs without review (i.e. before posting the using change) is acceptable.  Reasonable judgement is expected, lean towards review.

Third, established contributors will sometimes land "obvious" patches without review.  If you're new enough to the community to be reading this guide closely, this is not relevant for you (yet).  

Silence means "No"
------------------
As a general rule, silence on a review or RFC means "no".  It **does not** mean "no one cares, so go ahead".  There is a huge amount of coalition building and discussion which happens offline.  If you send out an RFC without talking it through with interested parties first, there is a good chance no one will have the time to read it and respond.  

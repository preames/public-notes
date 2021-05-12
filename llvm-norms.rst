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


What are "commit rights"?
--------------------------

LLVM grants commit rights much more freely than most other open source projects.  However, that's because the implied expectationss are very different.  In LLVM, having commit rights simply means that you are trusted to take the mechanical action of rebasing and landing an approved patch, and then respond promptly to post commit review.  It **does not** change any expectation around precommit review, or imply anything beyond a very basic level of trust.  

Silence means "No"
------------------
As a general rule, silence on a review or RFC means "no".  It **does not** mean "no one cares, so go ahead".  There is a huge amount of coalition building and discussion which happens offline.  If you send out an RFC without talking it through with interested parties first, there is a good chance no one will have the time to read it and respond.  

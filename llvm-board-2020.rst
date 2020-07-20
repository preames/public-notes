This is the draft form of my application to be on the LLVM foundation board.  If successful, the application becomes public, so I've decided simply to publish it from the beginning.  Current status is **very rough**.

Name (First and Surname) *
--------------------------
Philip Reames

Please summarize relevant contributions to the LLVM Project. These can include things such as patches, code ownership, bug reports, mailing list posts, blog posts, volunteering at LLVM events, organizing LLVM social events, contributing to the developer meeting paper committee, etc.
-------------------------------------------------------------------

LLVM contributor since 2013.  Major areas of (code) contribution:

* Main author of gc.statepoint infrastructure, and current defacto code owner of garbage collection support in LLVM
* Extensively contributed both directly and indirectly (though coworkers) to SCEV, IndVars, and much of our loop canonicalization infrastructure.  Recently became code owner.
* (Incrementally) rewrote most of LazyValueInfo and CorrelatedValuePropagation.
* Led effort to optimize unordered atomic loads and stores throughout middle end and x86 backend.  Contributed ~50% of the code directly.  
* Many smaller contributions through middle end optimizer and (to a much lesser degree) the x86 backend.

Non Technical Contributions

* Member of the recently established LLVM Security Group.
* Contact point for all Azul contributions to LLVM.  Representing LLVM internally (e.g. relicensing, etc..), and organizing organization contributions upstream, including internally focused developer education around LLVM community norms and processes.  
* Presenter at multiple LLVM Developer Conferences including one of the 2017 keynotes on the Falcon project.  Recently, most of my focus at developer meetings has been on the hallway track conversations, and the defacto "frontends for dynamic languages" working sessions which happen each year (whether formally organized or not). 
* Wrote "Performance Tips for Frontend Authors" and "LLVM Loop Terminology (and Canonical Forms)" doc pages.  Also contributed to a bunch of other docs in smaller one-off changes.

Indirect Contributions

* Points that follow are things which Azul does which I have had some role in steering.  Most of the work on these has not been my own, and others should get all the credit for making things actually happen.  :)
* Fuzzing, regression tracking, and quality improvements - We run one of the only large fuzzer deployments which actual runs generated code.  As a result of this, we catch a disportanate fraction of miscompiles.  We deliberate lag ToT by a few days so that our time and energy is spent on the harder subtle issues.  In addition to the normal "please revert patch X" cases, we've also found a number of deep and interesting bugs in core passes.  My favorite to date was the fuzzer finding incorrect nsw/nuw flag handling in GVN which had been present for almost a decade.  
* Falcon (our LLVM based compiler for Java bytecode) demonstrated that it was possible to develop compilers non-C family languages on LLVM, and achieve performance which beat existing state of the art approaches.  In the process of doing so, we fixed a number of issues, documented many of the items we stumbled across, and publically discussed most of the key design elements of our approach (including our mistakes).  I'd like to think this has positively impacted the broader LLVM ecosystem.  

TBD - How to describe Falcon, fuzzing efforts, etc..?

Why do you want to be on the LLVM Foundation board of directors?
-----------------------------------------------------------------

I believe strongly that the LLVM project has become a core piece of infrastructure and investment is needing accordingly.  I personally greatly appreciate various aspects of the community (e.g. professionalism, creative tension between pragmatism and perfectionism, and a refusal to get lost in bike sheding), but also see stress points forming as the community scales (e.g. infrastructure, decision making, review fragmentation).  I want to ensure the project continues to scale without loosing the aspects which have made it such a wonderful ecosystem in which to work these last few years.  

What experience or skills can you bring to the board? Which of the above programs could you help drive forward?
-------------------------

Helped to establish, and fundraise for initial New Haven Pride Center scholarship fund (https://www.newhavenpridecenter.org/youth/scholarship/).  That initial fund has now developed into five distinct scholarship funds with a total of 6 annual awards. 

The areas I'm most interested in contributing towards are scholarship grants, education oppurtunities for students getting started in the community (particular students from non-traditional backgrounds), and support of common project infrastructure.   I will also contribute in areas outside those foci, but they're the ones of most personal interest to me.  



We value diversity and representation of the various interested groups working on LLVM and using it. Do you consider yourself representative of a minority group, underrepresented geographic region, etc?
-----------------------------------------


Which program are you most interested in supporting?
-----------------------------------------------------

Educational Outreach

Diversity & Inclusion in Compilers and Tools

**Grants & Scholarships**

Infrastructure Support

What is your second choice program to support?
-----------------------------------------------

Educational Outreach

Diversity & Inclusion in Compilers & Tools

Grants & Scholarships

**Infrastructure Support**


How many hours a week can you dedicate to LLVM Foundation business?
Board members are expected to dedicate time to meetings and to the programs.
-----------------------------------------------------------------------------

Time availability will vary widely, but a minimum of 2-3 hours and sometimes much more.

Are you interested in a specific position on the board?
--------------------------------------------------------

No


Are you willing and able to help fundraise for the LLVM Foundation? We rely on donations to fund our programs and need board members to help find new sponsors and donors.
--------------------------------------------------------------------

Yes, with a paricular emphasis on 1) trying to establish periodic giving campaigns and otherwise diversify the foundations funding, and 2) separate dedicated funding sources for scholarships and student travel grants.

Is there anything else you would like to add for the board to consider?
------------------------------------------------------------------
No.

New this year, we will accept letters of recommendation to support your application. Please have your references send their letter of recommendation directly to us at boardapp@llvm.org. This is totally optional.
-------------------

I will not have any letters of recommendation

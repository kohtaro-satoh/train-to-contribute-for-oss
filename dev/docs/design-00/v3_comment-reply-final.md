Thank you for the warm and very generous reply — honestly wasn't 
expecting that kind of welcome!

Quick honesty first: this will be a side contribution outside my day 
job, so my pace will be steady but not fast — realistically a few hours 
per week.

For the near term, I'd like to prioritize reaching agreement on the 
specification and design with you before touching implementation. That 
kind of work is mostly about the fundamental mechanics of `lock()` — 
investigation, analysis, and design discussion — and it shouldn't be 
affected by concrete code changes elsewhere. Any local experiments I do 
will simply rebase onto the latest code as I go.

So please don't postpone your other fixes on my account — I'd be glad 
if you continue prioritizing your issue cleanup for now.

My proposed next steps:

1. Over the next 1–2 weeks, I'll study the codebase more deeply and 
   post a short design doc for your review.
2. Once we've aligned on the design, I'll start with a minimal PoC PR 
   (just the `serverId` parameter plumbing, no remote calls yet) to 
   validate the structural approach.
3. Then incrementally add remote locking, timeouts/leases, etc.

Looking at your recent work on #995 / #996, I noticed you use Epic 
tracking issues with sub-issues as the primary design format. I plan 
to follow that pattern — opening a new Epic issue (e.g., "Epic: 
Federation support for lockable resources") that references #321, 
and breaking the work into phased sub-issues later. Of course, if 
you'd prefer a different format, I'm happy to follow your lead.

Thanks again — this is very encouraging!
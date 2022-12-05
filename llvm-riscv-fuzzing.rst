-----------------------------
Fuzzing LLVM's RISCV Backend
-----------------------------

This document is a collection of notes for myself on attempts at fuzzing LLVM's riscv backend.  This is very much a WIP, and is not really intended to be read by another else just yet.  This is very much a background project, so updates will likely be slow.

.. contents::

Initial Attempt w/libFuzzer
---------------------------

I started with libfuzzer because we used to have OSSFuzz isel fuzzing for other targets, and I figured figuring out the build problem would be easy.  Yeah, not so much.

I was not able to get a working build of libfuzzer with ASAN.

I found a three stage build approach that "somewhat" worked.

stage1 - my normal LLVM dev build tree, clang enabled, Release+Asserts, nothing special

stage2 - "PATH=~/llvm-dev/build/bin/:$PATH CC=clang CXX=clang++ cmake -GNinja -DCMAKE_BUILD_TYPE=Release ../llvm-project/llvm -DLLVM_ENABLE_ASSERTIONS=ON -DLLVM_NO_DEAD_STRIP=ON -DLLVM_USE_SANITIZER=Address -DLLVM_TARGETS_TO_BUILD=X86 -DLLVM_BUILD_RUNTIME=Off -DLLVM_USE_SANITIZE_COVERAGE=On"

stage3 = "PATH=~/llvm-dev/fuzzer-build-stage1/bin/:$PATH CC=clang CXX=clang++ cmake -GNinja -DCMAKE_BUILD_TYPE=Release ../llvm-project/llvm -DLLVM_ENABLE_ASSERTIONS=ON -DLLVM_NO_DEAD_STRIP=ON -DLLVM_TARGETS_TO_BUILD="X86;RISCV" -DLLVM_BUILD_RUNTIME=Off -DLLVM_USE_SANITIZE_COVERAGE=On -DLLVM_TABLEGEN=/home/preames/llvm-dev/build/bin/llvm-tblgen "

I could not get the stage3 build to complete if I used the ASANified tblgen.  More than that, it seems clang from stage2 doesn't have a function ASAN.  Every attempt at using ASAN from that stage fails.  Cause unknown.

Once I got something which worked, I tried three experiments.

*Experiment 1 - " ./llvm-isel-fuzzer corpus/  -ignore_remaining_args=1 -mtriple riscv64 -O2"*

This used an empty corpus with default RISCV64 only (no extensions).  Ran for a couple hours, no failures found.


*Experiment 2 - "./llvm-isel-fuzzer corpus/ --help  -ignore_remaining_args=1 -mtriple riscv64 -O2 -mattr=+m,+d,+f,+c,+v"*

This used an empty corpus with a number of extensions enabled.  Ran for a weekend, no failures found.


*Experiment 3 - Ingest test/CodeGen/RISCV as starting corpus*

```
$ cat ingest-one.sh 
#set -x
set -e
SOURCE_FILE=$1

PATH=../build/bin:$PATH

fgrep "llvm.riscv" $SOURCE_FILE > /dev/null && exit 1

llvm-as $SOURCE_FILE -o corpus/tmp.bc
llc -O2 -march=riscv64 -mattr=+m,+d,+f,+c,+v -riscv-v-vector-bits-min=128 -o /dev/null < corpus/tmp.bc || exit 1
HASH=$(sha1sum corpus/tmp.bc | cut -f 1 -d " ")
echo "$SOURCE_FILE -> corpus/$HASH.bc"
mv corpus/tmp.bc "corpus/$HASH.bc"

$ PATH=../build/bin:$PATH find ../llvm-project/llvm/test/CodeGen/RISCV/ -name "*.ll" | xargs -l ./ingest-one.sh
```

This revealed an absolutely user interface disaster for libfuzzer.

Some tests deliberate check things which produce errors.  libFuzzer fails if the input corpus contains failures.  Since the exact setup is slightly different between the fuzzer binary, and llc, filtering out failures is a basically manual process.  I ran out of interest before finding useful results.

I also found that the public documentation on libfuzzer command line arguments is simply wrong in many cases.  Nor does the binary support useful -help output of any kind.

I consider this effort to have been a failure, and do not currently plan to spend more time on libfuzzer.  The fact that I, a longstanding LLVM dev, can't figure out how to actually build the damn thing in a useful way says all too much right there.

Reference save:

* https://github.com/google/oss-fuzz/pull/7179#issuecomment-1092802635
* https://github.com/google/oss-fuzz/commit/e0787861af03584754923979e76a243080e7dd96
* https://bugs.chromium.org/p/oss-fuzz/issues/detail?id=27686
* https://oss-fuzz-build-logs.storage.googleapis.com/log-9d455709-b52a-4ee0-8494-4a7e2529d5ff.txt
* https://oss-fuzz-build-logs.storage.googleapis.com/log-f98c7f04-9b4c-43da-9a7c-3559a6a9b3dd.txt
* https://oss-fuzz-build-logs.storage.googleapis.com/log-d902e118-7a63-439a-92f4-31bfaaf374f6.txt
* https://llvm.org/docs/FuzzingLLVM.html (build instructions *do not* work)

Brute Force via csmith and llvm-stress
--------------------------------------

I have written some simple shell scripts to do brute force fuzzing of clang and llc targetting RISCV driven by csmith and llvm-stress respectively.  As of this update, I have run ~100k unique csmith tests and ~10m unique llvm-stress tests.  So far, I have found no compiler crash bugs.  I am not running the resulting code, so I may have missed execution bugs.


AFL - Upcoming
----------------

I'm planning to spend some time playing with afl-fuzz driving llc.  My hope is that the user interface is more practically approachable.  In theory, the fuzz rate will be lower due to the need to fork and instrument, but so be it.



Other ideas to investigate
--------------------------

Using JavaFuzzer for C++?  Or maybe the approach John Regehr's student is using with great success on AArch64 right now?

Rather than just fuzzing for crashes, fuzz using alive2 for miscompiles?  Harder for backend, but maybe through IR phase?  Or just find problems which depend on target hooks?







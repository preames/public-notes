This document discusses how a JIT compiler (or other code generator) can generate symbol information for use with the Linux perf utility.  This is written from the perspective of a JIT implementor, but might be of some interest to others as well.  This is mostly a summary of information available elsewhere, but at time of writing I couldn't find such a summary.  

There are two major mechanisms supported by perf for getting symbols for dynamically generated code: perf map files, and jitdump files.

Perf Map
  A perfmap is a textual file which maps address ranges to symbol names.  It has no other content and does not support disassembly or annotation.  
  
  I couldn't find a formal description of the format anywhere, but the format appears to have one entry per line of the form "<hex_start_addr> <hex_size> <symbol_string".  An example valid entry would be "30affdb58 a20 my_func".
  
  Perf map files are looked for in a magic path by the perf utility.  That path is /tmp/perf-<pid>.map where <pid> is the pid of the process containing the generated code.  This pid is recorded in the perf.data file, so offline analysis is supported.  You can copy these files between machines if needed.  There's no graceful handling of pid collisions, and no machanism to cleanu old perfmap files which I found.
  
  The format does not support relocation of code, or recycling of memory for different executible contents.  What happens if you have overlapping ranges in a file is unspecified.  
  
Jitdump
  The jitdump format is a binary format which is much covers a much broader range of use cases.  There is a `formal spec <https://raw.githubusercontent.com/torvalds/linux/master/tools/perf/Documentation/jitdump-specification.txt>_` for the binary format.  In addition to basic symbol resolution, jitdump supports disassembly/annotaton and code relocation.
  
  To work with jitdump files, you have to use "perf inject" to produce a perf.data file which contains both the raw perf.data and the additional jitdump information.  The location of the jitdump file on disk is not documented, and I haven't yet tracked it down.  Once injected, the combined data.perf file can be moved to other machines for analysis.  
  

This document discusses how a JIT compiler (or other code generator) can generate symbol information for use with the Linux perf utility.  This is written from the perspective of a JIT implementor, but might be of some interest to others as well.  This is mostly a summary of information available elsewhere, but at time of writing I couldn't find such a summary.  

There are two major mechanisms supported by perf for getting symbols for dynamically generated code: perf map files, and jitdump files.

Perf Map
  A perfmap is a textual file which maps address ranges to symbol names.  It has no other content and does not on its own [1]_ support disassembly or annotation.  
  
  I couldn't find a formal description of the format anywhere, but the format appears to have one entry per line of the form "<hex_start_addr> <hex_size> <symbol_string".  An example valid entry would be "30affdb58 a20 my_func".
  
  Perf map files are looked for in a magic path by the perf utility.  That path is /tmp/perf-<pid>.map where <pid> is the pid of the process containing the generated code.  This pid is recorded in the perf.data file, so offline analysis is supported.  You can copy these files between machines if needed.  There's no graceful handling of pid collisions, and no machanism to cleanu old perfmap files which I found.
  
  The format does not support relocation of code, or recycling of memory for different executible contents.  What happens if you have overlapping ranges in a file is unspecified.  
  
Jitdump
  The jitdump format is a binary format which is much covers a much broader range of use cases.  There is a `formal spec <https://raw.githubusercontent.com/torvalds/linux/master/tools/perf/Documentation/jitdump-specification.txt>`_ for the binary format.  In addition to basic symbol resolution, jitdump supports disassembly/annotaton and code relocation.
  
  To work with jitdump files, you have to use "perf inject" to produce a perf.data file which contains both the raw perf.data and the additional jitdump information.  The location of the jitdump file on disk is not documented, and I haven't yet tracked it down.  Once injected, the combined perf.jit.data file can be moved to other machines for analysis.  
  
From what I can tell, jitdump provides a strict superset of the functionality of perf map files.  Despite this, perf map appears to be much more widely used.  It's not clear to me why this is true; the main value I see in perf map files is that they're easy to generate by hand or by simple scripting from other information sources.

Example Command Sequences
--------------------------

perf map::

  perf record <command-of-interest>
  # remember to copy the /tmp/perf-<pid>.map along with the perf.data file
  # if analyzing off box
  perf report
  
jitdump::

  perf record <command-of-interest>
  perf inject --jit -i perf.data -o perf.jit.data
  # move perf.jit.data around if needed
  perf report -i perf.jit.data

Potential Gotchas
-----------------

Support for both mechanisms were added to perf relatively recently.  As perf is version locked to the kernel of the system, this implies that currently supported releases of some older distros contain perf versions which don't support either feature.  Unfortunately, there's no graceful error reporting; symbols simply fail to load.  I ended up resorting to grepping through strace output to confirm whether the perf binary I was using tried to load the perf map file.  This was the only conclusive way I found to distinguish between malformed perf map files and versions of perf lacking support.  

For some reason I've yet to understand, certain types of memory regions cause perf to fail to collect symbolizable traces.  This is particularly confusing as inspecting the raw data file with perf script and/or perf report shows addresses which map to valid entries in a perf map file, but for some reason the way memory was obtained during the perf record run effects symbolization.  I've only see this with perf maps; I haven't tried the same experiment with a jitdump setup just yet.

Useful References
------------------

The wasmtime folks have a `nice description <https://bytecodealliance.github.io/wasmtime/examples-profiling-perf.html>`_ of using a jitdump based mechanism from a user perspective.

Brenden Gregg has a post on using perf map files to generate `flame graphs for v8 <http://www.brendangregg.com/blog/2014-09-17/node-flame-graphs-on-linux.html>`_.  He also has a lot of other generally awesome perf stuff, but most of it's focused on statically compiled code.  

`perf-map-agent <https://github.com/jvm-profiling-tools/perf-map-agent>`_ and `perf-jitdump-agent <https://github.com/sfriberg/perf-jitdump-agent>`_ are useful examples of how to generate the corresponding file formats.  These are each jvmti agents for Java for each of the corresponding workflows.  

Footnotes
----------

.. [1] Several of the perf commands allow you to provide an alternate path to the objdump binary.  If you have an alternate source of disassembly of some of the methods named in the perf map file, you can write a shim script which wraps the real objdump, intercepts the disassembly request sent to objdump for a particular symbol name, and provides the alternate disassembly.  


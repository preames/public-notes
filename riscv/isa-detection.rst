-------------------------------
User Mode ISA Detection (RISCV)
-------------------------------

.. contents::


AT_HWCAP
--------

.. code::

   #include <sys/auxv.h>
   #include <stdio.h>

   int main() {
     unsigned long hw_cap = getauxval(AT_HWCAP);
     for (int i = 0; i < 26; i++) {
       char Letter = 'A' + i;
       printf("%c %s\n", Letter, hw_cap & (1 << i) ? "detected" : "not found");
     }
     return 0;
   }

Problems:

* Only a few of the bits actually correspond the useful single letter extensions.  The rest are wasted bits, and there's none for e.g. Zba.
* Unclear specification.  Exactly which *version* from which *specification document* does each bit correspond to?  See `minutia <https://github.com/preames/public-notes/blob/master/riscv-spec-minutia.rst#zicntr>`_ for some of the ambiguities.
* V - Is this V1.0 or THeadVector?  Custom kernels are known to report the later as 'V'.

riscv_hwprobe
-------------

syscall
  See RISE's RISC-V Optimization Guide for `an example <https://gitlab.com/riseproject/riscv-optimization-guide/-/blob/main/riscv-optimization-guide.adoc?ref_type=heads#user-content-detecting-risc-v-extensions-on-linux>`_.  As noted there, the syscall was added in 6.4.  Attempting to use it on an earlier kernel will return ENOSYS.  The syscall is a relatively cheap syscall, but you do have the transition overhead.  Cost is probably something in the 1000s of instructions.

vDSO
  Also added in 6.4 (so there is no kernel version with the syscall, but without the vDSO).  Caches the key/value for the intersection of the flags for all cpus.  Will return results without a syscall if either a) all_cpus is queried (i.e. no cpu set given to the call) or b) underlying system is homogeneous.  The vDSO symbol name is `__vdso_riscv_hwprobe`.  I've been told that binding a weak symbol with this name is sufficient, and that LDD will resolve it per normal dynamic link rules, but I haven't yet gotten this working.

glibc
  The patch for the glibc wrapper has landed, but *is not yet released*.  It is likely to be included in glibc 2.40 which is expected in Aug 2024, but should not be considered ABI stable until it is released.  `glibc provides <https://github.com/bminor/glibc/blob/master/sysdeps/unix/sysv/linux/riscv/sys/hwprobe.h>`_ two entry points `__riscv_hwprobe` - which is just a wrapper around the vDSO - and `__riscv_hwprobe_one` - an inline function specialized for the common single key case.

qemu-user
  It is currently an open question whether the vDSO above is supported by qemu-riscv64.  Initial testing seems to indicate no, but user error has not yet been disproven.

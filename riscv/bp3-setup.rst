-----------------------
Banana PI 3 Setup Notes
-----------------------

This board was released in Q2 2024, and appears to be the first relatively widely available board with vector 1.0.  The ISA is rva22u w/V and VLEN=256.  This page is my notes from trying to set one up as a development board.

`BPi-F3 Datasheet https://docs.banana-pi.org/en/BPI-F3/SpacemiT_K1_datasheet>`_,  `Spacemit-K1 Datasheet <https://developer.spacemit.com/#/documentation?token=DBd4wvqoqi2fiqkiERTcbEDknBh>`_

To purchase: `AliExpress <https://a.aliexpress.com/_mOI0MCI>`_, `Amazon <https://www.amazon.com/BPI-F3-RISC-V-K1-SBC-Performance/dp/B0D44TH59S?th=1>`_

.. contents::


Download the OS Image
---------------------

Directly from the vendor `here <https://docs.banana-pi.org/en/BPI-F3/BananaPi_BPI-F3#_system_image>`_.  Make sure you grab the SD card images.  The easiest downloads are the google drive ones unless you speak Chinese.  


Format/Partition the SD Card
----------------------------

First, figure out which device corresponds to the your SD card.  The rest of this assumes it is `/dev/sda` -- make sure you change for your environment!

.. code::

   lsblk

Zero the entire SD card.  Do not skip this step, or you get weird hangs at boot time.

.. code::

   sudo dd if=/dev/zero of=/dev/sda bs=4096 status=progress

Format the partion table, etc...  (`For a lot more detail on this step <https://linuxize.com/post/how-to-format-usb-sd-card-linux/>`_.)

.. code::
   
   sudo parted /dev/sda --script -- mklabel msdos
   sudo parted /dev/sda --script -- mkpart primary fat32 1MiB 100%
   sudo mkfs.vfat -F32 /dev/sda1
   sudo parted /dev/sda --script print

Copy the contents of your img to the device.

.. code::
  
   sudo dd if=/home/preames/DevBoards/BananaPI/bianbu-23.10-desktop-k1-v1.0rc3-release-20240525133016.img of=/dev/sda status=progress bs=4M

Use `gparted`, or tool of your choice, to resize the final fat32 partition to fill available space.  If you skip this step, installing new packages will fail due to insufficient space.

Boot It
-------

I plugged in a HDMI monitory, keyboard, and mouse.  Then went through the initial setup to e.g. configure WiFi.  After that, I switched to SSH login.

If this step fails (i.e. hangs), go back and read the warnings on the zeroing and formatting section again.

Initial Setup
-------------

Do the usual update:

.. code::

   sudo apt-get update
   sudo apt-get upgrade

Install the usual packages:

.. code::

   sudo apt-get --assume-yes install emacs man-db libc6-dev dpkg-dev make build-essential binutils binutils-dev gcc g++ autoconf python3 git clang cmake patchutils ninja-build flex bison

Getting `perf` working
----------------------

Do the following:

.. code::

   git clone https://github.com/BPI-SINOVOIP/pi-linux
   cd pi-linux
   uname --all
   # Checkout the right branch for your kernel version
   git checkout linux-6.1.15-k1
   pushd tools/perf/pmu-events
   ./jevents.py riscv arch pmu-events.c
   popd
   sudo apt install libelf-dev libdw-dev flex bison
   sudo make -C tools/ NO_LIBBPF=1 prefix=/usr/local/ perf_install

These instructions are inspired by `this blog post <https://dev.to/luzero/bringing-up-bpi-f3-part-25-27o4>`_.  Note that I'm running on the  `bianbu-23.10-desktop-k1-v1.0rc3-release-20240525133016` image, and that the default counter names appear to work for me.

LLVM Native Build (Unsuccessful)
--------------------------------

I attempted to build LLVM natively on the board.  The filesystem is insanely slow, so just getting a git checkout in place took a while; starting from a zip file probably would have been a better idea.

I tried "ninja -j6" and got lots of OOMs.  I tried building individually to clear large files, and made some progress, but the build time is extremely high.  I hit what appeared to be lack of forward progress after 1 hour on a single source file, and then switched away to other tasks.  It may be this can work end to end, but I haven't gotten it yet.

Other References
----------------

https://dev.to/luzero/bringing-up-bpi-f3-part-1-3bm4

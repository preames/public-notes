-----------------------
Banana PI 3 Setup Notes
-----------------------

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

Format the partion table, etc...  (`For a lot more detail on this step <https://linuxize.com/post/how-to-format-usb-sd-card-linux/`_.)

.. code::
   sudo parted /dev/sda --script -- mklabel msdos
   sudo parted /dev/sda --script -- mkpart primary fat32 1MiB 100%
   sudo mkfs.vfat -F32 /dev/sda1
   sudo parted /dev/sda --script print

Copy the contents of your img to the device.

.. code::
  
   sudo dd if=/home/preames/DevBoards/BananaPI/bianbu-23.10-desktop-k1-v1.0rc3-release-20240525133016.img of=/dev/sda status=progress bs=4M


Boot It
-------

I plugged in a HDMI monitory, keyboard, and mouse.  Then went through the initial setup to e.g. configure WiFi.  After that, I switched to SSH login.

Initial Setup
-------------

Do the usual update:

.. code::

   sudo apt-get update
   sudo apt-get upgrade

Install the usual packages:

.. code::

   sudo apt-get --assume-yes install emacs man-db libc6-dev dpkg-dev make build-essential binutils binutils-dev gcc g++ autoconf python3 git clang cmake patchutils ninja-build flex bison

Other References
----------------

https://dev.to/luzero/bringing-up-bpi-f3-part-1-3bm4

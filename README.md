# lvmsync

Have you ever wanted to do a partial sync on a block device, possibly over a
network, but were stymied by the fact that rsync just didn't work?

Well, fret no longer.  As long as you use LVM for your block devices, you
too can have efficient delta-transfer of changed blocks.


## What is it good for?

Mostly, transferring whole block devices from one machine to another, with
minimal downtime.  Until now, you had to shutdown your service/VM/whatever,
do a big cross-network dd (using netcat or something), and wait while all
that transferred.


## How does it work?

By the magic of LVM snapshots.  In short, what `lvmsync` allows you to do
is:

1. Take a snapshot of an existing LV.
1. Transfer the entire snapshot over the network, while whatever uses the
block device itself keeps running.
1. When the initial transfer is finished, you shutdown/unmount/whatever the
initial block device
1. Run lvmsync over the existing LV and it's snapshot
1. The only thing transferred over the network is the blocks that have
changed (which, hopefully, will be minimal)
1. If you're paranoid, you can md5sum the content of the source and
destination block devices, to make sure everything's OK (although this will
trash your performance benefits)
1. Bring the service/VM/whatever back up in it's new home in a *much*
shorter (as in, "orders of magnitude") time than was previously possible.


## Installation

On the machine you're transferring from, you'll need `lvmsync`, `dmsetup`,
and `ssh`.

On the machine you're transferring *to*, you'll need `lvmsync` and `sshd`.


## How do I use it?

At present, the only part that is automated is the step of transferring the
snapshot changes -- the rest you'll have to handle by hand (for now).

To transfer changes to another machine, call `lvmsync` like this:

    lvmsync <origin LV> <destserver>:<destblock>

This requires that `lvmsync` is installed on `<destserver>`, and that you
have the ability to SSH into `<destserver>` as root.  All data transfer
takes place over SSH, because we don't trust any network, and it simplifies
so many things (such as link-level compression, if you want it).  If CPU is
an issue, you shouldn't be running LVM on your phone anyway.

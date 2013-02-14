# lvmsync

Have you ever wanted to do a partial sync on a block device, possibly over a
network, but were stymied by the fact that rsync just didn't work?

Well, fret no longer.  As long as you use LVM for your block devices, you
too can have efficient delta-transfer of changed blocks.


## What is it good for?

Mostly, transferring entire block devices from one machine to another, with
minimal downtime.  Until now, you had to shutdown your service/VM/whatever,
do a big cross-network dd (using netcat or something), and wait while all
that transferred.

`lvmsync` allows you to use the following workflow to transfer a block
device "mostly live" to another machine:

1. Take a snapshot of an existing LV.
1. Transfer the entire snapshot over the network, while whatever uses the
block device itself keeps running.
1. When the initial transfer is finished, you shutdown/unmount/whatever the
initial block device.
1. Run lvmsync on the snapshot to transfer the changed blocks
 * The only thing transferred over the network is the blocks that have
   changed (which, hopefully, will be minimal)
1. If you're paranoid, you can md5sum the content of the source and
destination block devices, to make sure everything's OK (although this will
destroy any performance benefit you got by running lvmsync in the first
lace)
1. Bring the service/VM/whatever back up in it's new home in a *much*
shorter (as in, "orders of magnitude") time than was previously possible.

`lvmsync` also has a basic "snapshot-and-rollback" feature, where it can
save a copy of the data in the LV that you're overwriting to a file for
later application if you need to rollback.  See "Snapback support" under
"How do I use it?" for more details.


## How does it work?

By the magic of LVM snapshots.  `lvmsync` is able to read the metadata that
device-mapper uses to keep track of what parts of the block device have
changed, and use that information to only send those modified blocks over
the network.

If you're really interested in the gory details, there's a brief "Theory of
Operation" section at the bottom of this README, or else you can just head
straight for the source code.


## Installation

On the machine you're transferring from, you'll need have `dmsetup` and
`ssh` installed and available on the PATH, and an installation of Ruby 1.8
(or later).  Then just copy the `lvmsync` script to somewhere in root's
PATH.

On the machine you're transferring *to*, you'll need `sshd` installed and
available for connection, and an installation of Ruby 1.8 (or later).  Then
just copy the `lvmsync` script to somewhere in root's PATH.


## How do I use it?

For an overview of all available options, run `lvmsync -h`.


### Efficient block device transfer

At present, the only part of the block device syncing process that is
automated is the actual transfer of the snapshot changes -- the rest (making
the snapshot, doing the initial transfer, and stopping all writes to the LV)
you'll have to do yourself.  Those other steps aren't difficult, though, and
are trivial to script to suit your local environment (see the example,
below).

Once you've got the snapshot installed, done the initial sync, and stopped
I/O, you just call `lvmsync` like this:

    lvmsync <snapshot LV device> <destserver>:<destblock>

This requires that `lvmsync` is installed on `<destserver>`, and that you
have the ability to SSH into `<destserver>` as root.  All data transfer
takes place over SSH, because we don't trust any network, and it simplifies
so many things (such as link-level compression, if you want it).  If CPU is
an issue, you shouldn't be running LVM on your phone to begin with.

The reason why `lvmsync` needs you to specify the snapshot you want to sync,
and not the base LV, is that you might have more than one snapshot of a
given LV, and while we can determine the base LV given a snapshot, you can't
work out which snapshot to sync given a base LV.  Remember to always specify
the full device path, not just the LV name.


#### Example

Let's say you've got an LV, named `vmsrv1/somevm`, and you'd like to
synchronise it to a new VM server, named `vmsrv2`.  Assuming that `lvmsync` is
installed on `vmsrv2` and `vmsrv2` has an LV named `vmsrv2/somevm` large
enough to take the data, the following will do the trick rather nicely (all
commands should be run on `vmsrv1`:

    # Take a snapshot before we do anything, so LVM will record all changes
    # made while we're doing the initial sync
    lvcreate --snapshot -L10G -n somevm-lvmsync vmsrv1/somevm

    # Pre-sync all data across -- this will take some time, but while it's
    # happening the VM is still serving traffic.  pv is a great tool for
    # showing you how fast your data's moving, but you can leave it out of
    # the pipeline if you don't have it installed.
    dd if=/dev/vmsrv1/somevm bs=1M | pv -ptrb | ssh root@vmsrv2 dd of=/dev/vmsrv2/somevm

    # Shutdown the VM -- the command you use will probably vary
    virsh shutdown somevm
    
    # Once it's shutdown and the block device isn't going to be written to
    # any more, then you can run lvmsync
    lvmsync /dev/vmsrv1/somevm-lvmsync vmsrv2:/dev/vmsrv2/somevm
    
    # You can now start up the VM on vmsrv2, after a fairly small period of
    # downtime.  Once you're done, you can remove the snapshot and,
    # presumably, the LV itself, from `vmsrv1`


### Snapback support

In addition to being able to efficiently transfer the changes to an LV
across a network, `lvmsync` now supports a simple form of point-in-time
recovery, which I've called 'snapback'.

The way this works is startlingly simple: as `lvmsync` writes the changed
blocks out to the destination block device, it reads the data that is being
overwritten, and stores it to a file (specified with the `--snapback`
option).  The format of this file is the same as the wire protocol that
`lvmsync` uses to transfer changed blocks over the network.  This means
that, in the event that you need to rollback a block device to an earlier
state, you can do so by simply applying the saved snapback files created
previously, until you get to the desired state.


#### Example

To setup a snapback process, you need to have a local LV, with a snapshot,
whose contents have been sent to a remote server, perhaps something like
this:

    lvcreate --snapshot -L10G -n somevm-snapback vmsrv1/somevm
    dd if=/dev/vmsrv1/somevm bs=1M | pv -ptrb | \
         ssh root@vmsrv2 dd of=/dev/vmsrv2/somevm

Now, you can run something like the following periodically (say, out of cron
each hour):

    lvcreate --snapshot -L10G -n somevm-snapback-new vmsrv1/somevm
    lvmsync /dev/vmsrv1/somevm-snapback vmsrv2:/dev/vmsrv2/somevm --snapback \
         /var/snapbacks/somevm.$(date +%Y%m%d-%H%M)
    lvremove -f vmsrv1/somevm-snapback
    lvrename vmsrv1/somevm-snapback-new somevm-snapback

This will produce files in /var/snapbacks named `somevm.<date-time>`.  You
need to create the `somevm-snapback-new` snapshot before you start
`lvmsync`, so that you can guarantee no changes won't get noticed.

There are some fairly large caveats to this method -- the LV will still be
collecting writes while you're transferring the snapshots, so you won't get
a consistent snapshot (in the event you have to rollback, it's almost
certain you'll need to fsck).  You'll almost certainly want to incorporate
some sort of I/O freezing into the process, but the exact execution of that
is system-specific, and left as an exercise for the reader.

Restoring data from a snapback setup is straightforward -- just take each
snapback **in reverse order** and run it through `lvmsync --apply` on the
destination machine (`vmsrv2` in our example).  Say at 1145 `vmsrv1`
crashed, and it was determined that you needed to rollback to the state of
the system at 8am.  You could do this:

    lvmsync --apply /var/snapbacks/somevm.20120119-1100 /dev/vmsrv2/somevm
    lvmsync --apply /var/snapbacks/somevm.20120119-1000 /dev/vmsrv2/somevm
    lvmsync --apply /var/snapbacks/somevm.20120119-0900 /dev/vmsrv2/somevm

And you're done -- `/dev/vmsrv2/somevm` is now at the state it was at at
8am.  A whole pile of fsck will no doubt be required, but hopefully you'll
still be able to salvage *something*.

If you're wondering why I only restored the 0900 snapback, and not the 0800
one, it's because the snapback made at 0900 copied the changes that were sent
at 0800 (and about to be overwritten at 0900) and wrote them to the 0900
snapback file.  Confused much?  Good.


### Transferring snapshots on the same machine

If you need to transfer an LV between different VGs on the same machine,
then running everything through SSH is just an unnecessary overhead.  If you
instead just run `lvmsync` without the `<destserver>:` in the destination
specification, everything runs locally, like this:

    lvmsync /dev/vg0/srclv-snapshot /dev/vg1/destlv

All other parts of the process (creating the snapshot, doing the initial
data move with `dd`, and so on) are unchanged.

As an aside, if you're trying to move LVs between PVs in the same VG, then
you don't need `lvmsync`, you need `pvmove`.


## Theory of Operation

This section is for those people who can't sleep well at night without
knowing the magic behind the curtain (and to remind myself occasionally how
this stuff works).  It is completely unnecessary to read this section in
order to work lvmsync.

First, a little bit of background about how snapshot LVs work, before I
describe how lvmsync makes use of them.

An LVM snapshot "device" is actually not a block device in the usual sense. 
It isn't just a big area of disk space where you write things.  Instead, it
is a "meta" device, which points to both an "origin" LV, which is the LV
from which the snapshot was made, and a "metadata" LV, which is where the
magic happens.

The "metadata" LV is a list of "chunks" of the origin LV which have been
modified, along with the original contents of those chunks.  In a way, you
can think of it as a sort of "binary diff", which says "these are the ways
in which this snapshot LV differs from the origin LV".  When a write happens
to the origin LV, this "diff" is potentially modified to maintain the
original "view" from the time the snapshot was taken.

(Sidenote: this is why you can write to snapshots -- if you write to a
snapshot, the "diff" is written to some more, to say "here are some more
differences between the origin and the snapshot").

From here, it shouldn't be hard to work out how LVM uses the combination of
the origin and metadata LVs to give you a consistent snapshot view -- when
you ask to read a chunk, LVM looks in the metadata LV to see if it has the
chunk in there, and if not it can be sure that the chunk hasn't changed, so
it just reads it from the origin LV.  Miiiiighty clever!

In lvmsync, we only make use of a tiny fraction of the data stored in the
metadata LV for the snapshot.  We don't care what the original contents were
(they're what we're trying to get *away* from).  What we want is the list of
which chunks have been modified, because that's what we use to work out
which blocks on the original LV we need to copy across.  lvmsync never
*actually* reads any disk data from the snapshot block device itself -- all
it reads is the list of changed blocks, then it reads the changed data from
the original LV (which is where the modified blocks are stored).

By specifying a snapshot to lvmsync, you're telling it "this is the list of
changes I want you to copy" -- it already knows which original LV it needs
to copy from (the snapshot metadata has that info available).


## See Also

Whilst I think `lvmsync` is awesome (and I hope you will too), here are some
other tools that might be of use to you if `lvmsync` doesn't float your
mustard:

* [`blocksync.py`](http://www.bouncybouncy.net/programs/blocksync.py) --
  Implements the "hash the chunks and send the ones that don't match"
  strategy of block device syncing.  It needs to read the entire block
  device at each end to work out what to send, so it's not as efficient,
  but on the other hand it doesn't require LVM.

* [`bdsync`](http://bdsync.rolf-fokkens.nl/) -- Another "hash the chunks"
  implementation, with the same limitations and advantages as
  `blocksync.py`.

* [`ddsnap`](http://zumastor.org/man/ddsnap.8.html) -- Part of the
  "Zumastor" project, appears to provide some sort of network-aware block
  device snapshotting (I'm not sure, the Zumastor homepage includes the word
  "Enterprise", so I fell asleep before finishing reading).  Seems to
  require kernel patches, so there's a non-trivial barrier to entry, but
  probably not such a big deal if you're after network-aware snapshots as
  part of your core infrastructure.

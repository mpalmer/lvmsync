#!/usr/bin/env python

# Transfer a set of changes made to the origin of a snapshot LV to a block
# device on a remote system.
#
# Usage: Start with lvmsync --help, or read the README for all the gory
# details
#
# Python port of the ruby version

import sys, re, commands, struct, time
from optparse import OptionParser

PROTOCOL_VERSION = "lvmsync PROTO[2]"

def main():
	parser = OptionParser()
	parser.add_option('-v', '--verbose', action='store_true', dest='verbose', default=False, help="Run verbosely")
	parser.add_option('--server', action='store_true', dest='server', default=False, help="Run in server mode (not intended for interactive use)")
	parser.add_option('-b', '--snapback', dest='snapback', help="Make a backup snapshot file on the destination")
	parser.add_option('-a', '--apply', action='store_true', dest='apply', default=False, help="Apply mode: write the contents of a snapback file to a device")
	parser.add_option('-p', '--patch', action='store_true', dest='patch', default=False, help= "Patch mode: create a patch file that can be applied to the destdevice later via apply mode")
	parser.add_option('-q', '--quiet', action='store_true', dest='quiet', default=False, help= "Do not output anything except errors")

	(options, args) = parser.parse_args()

	if options.apply:
		if len(args) < 1:
			print >> sys.stderr, "No snapback file specified."
			sys.exit(1)

		if len(args) < 2:
			print >> sys.stderr, "No destination device specified."
			sys.exit(1)

		options.snapfile = args[0]
		options.device = args[1]
		run_apply(options)

	elif options.patch:
		if len(args) < 1:
			print >> sys.stderr, "No destination patch file specified."
			sys.exit(1)

		if len(args) < 2:
			print >> sys.stderr, "No snapshot device specified."
			sys.exit(1)

		options.patchfile = args[0]
		options.desthost = ''
		options.destdev = ''
		options.snapdev = args[1]

		if options.patchfile == '-':
			options.quiet = True
			options.verbose = False
		run_client(options)

	elif options.server:
		if len(args) < 1:
			print >> sys.stderr, "No destination block device specified.  WTF?"
			sys.exit(1)

		options.destdev = args[0]
		run_server(options)
	else:
		if len(args) < 1:
			print >> sys.stderr, "ERROR: No snapshot specified.  Exiting."
			sys.exit(1)

		if len(args) < 2:
			print >> sys.stderr, "No destination specified."
			sys.exit(1)

		(dev, host) = (':'+args[1]).split(':', 3)[::-1]
		options.snapdev = args[0]
		options.desthost = host
		options.destdev = dev
		run_client(options)

def run_server(opts):
	destdev = opts.destdev

	handshake = sys.stdin.readline().strip()
	if handshake != PROTOCOL_VERSION:
		print >> sys.stderr, "Handshake failed; protocol mismatch? (saw '%s'' expected '%s'" % (handshake, PROTOCOL_VERSION)
		sys.exit(1)

	if opts.snapback:
		snapback = open(opts.snapback, 'w')
		try:
			snapback.write( PROTOCOL_VERSION )
			process_dumpdata(sys.stdin, destdev, snapback)
		finally:
			snapback.close()
	else:
		process_dumpdata(sys.stdin, destdev, None)

def process_dumpdata(instream, destdev, snapback = None):
	dest = open(destdev, 'w+')
	try:
		while True:
			header = instream.read(12)
			if not header:
				break
			offset, chunksize = struct.unpack("QI", header)[0], struct.unpack(">QI", header)[1]
			dest.seek (offset * chunksize)
			if snapback:
				snapback.write(header)
				snapback.write(dest.read(chunksize))
				dest.seek(offset * chunksize)
			dest.write(instream.read(chunksize))
	finally:
		dest.close()

def run_client(opts):
	snapshot = opts.snapdev
	remotehost = opts.desthost
	remotedev = opts.destdev

	snapshotdm = canonicalise_dm(snapshot)

	# First, read the dm table so we can see what we're dealing with
	dmtable = read_dm_table()
	dmlist = read_dm_list()

	if snapshotdm not in dmlist:
		print >> sys.stderr, "Could not find dm device '%s' (name mangled to '%s')" % (snapshot, snapshotdm)
		sys.exit(1)

	if dmtable[snapshotdm][0]['type'] != 'snapshot':
		print >> sys.stderr, "%s does not appear to be a snapshot" % (snapshot, )
		sys.exit(1)

	origindm = dm_from_devnum(dmtable[snapshotdm][0]['args'][0], dmlist)

	if not origindm:
		print >> sys.stderr, "CAN'T HAPPEN: No origin device for %s found" % (snapshot, )
		sys.exit(1)

	if opts.verbose: print "Found origin dm device: %s" % (origindm, )

	exceptiondm = dm_from_devnum(dmtable[snapshotdm][0]['args'][1], dmlist)

	if not exceptiondm:
		print >> sys.stderr,  "CAN'T HAPPEN: No exception list device for %s found!" % (snapshot, )

	# Since, in principle, we're not supposed to be reading from the CoW
	# device directly, the kernel makes no attempt to make the device's read
	# cache stay in sync with the actual state of the device.  As a result,
	# we have to manually drop all caches before the data looks consistent. 
	# PERFORMANCE WIN!
	fd = open("/proc/sys/vm/drop_caches", 'w')
	try:
		fd.write ("3")
	finally:
		fd.close()

	if opts.verbose: print "Reading snapshot metadata from /dev/mapper/%s" % (exceptiondm, )
	if opts.verbose: print "Reading changed chunks from /dev/mapper/%s" % (origindm, )

	xfer_count = 0
	total_size = 0
	chunksize = None
	snapback = '' 
	if opts.snapback: snapback = "--snapback %s" % (opts.snapback, )

	if remotehost:
		remoteserver = os.popen('ssh %s lvmsync.py --server %s %s' % (remotehost, snapback, remotedev), 'w')
	elif opts.patch:
		if opts.patchfile == '-':
			remoteserver = sys.stdout
		else:
			remoteserver = open(opts.patchfile, 'w')
	else:
		remoteserver = os.popen('lvmsync.py --server %s %s' % (snapback, removedev), 'w')

	try:
		remoteserver.write(PROTOCOL_VERSION + "\n")

		origindev = open('/dev/mapper/' + origindm, 'r')
		try:
			snapdev = open('/dev/mapper/' + exceptiondm, 'r')
			try:
				chunksize = read_header(snapdev)

				snapdev.seek(chunksize)
				in_progress = True
				t = time.time()
				while in_progress:
					for notused in range(0, chunksize / 16):
						(origin_offset, snap_offset) = struct.unpack('QQ', snapdev.read(16))
						origin_offset = ntohq(origin_offset)
						snap_offset = ntohq(snap_offset)
						if snap_offset == 0:
							in_progress = False
							break
						xfer_count += 1
						if opts.verbose: print "Sending chunk %d" % (origin_offset, )
						origindev.seek (origin_offset * chunksize)
						# Ruby version has a bug that results in only the second value being sent in network order
						send_chunksize = struct.unpack('I', struct.pack('>I', chunksize) )[0]
						remoteserver.write ( struct.pack('QI', htonq(origin_offset), send_chunksize) )
						remoteserver.write ( origindev.read(chunksize) )

					if in_progress: snapdev.seek (chunksize * chunksize / 16, 1)
					if not opts.quiet: 
						print "\r%.0fB/s" % (chunksize / (time.time() - t), ) ,
						sys.stdout.flush()
					t = time.time()
			finally:
				snapdev.close()

			origindev.seek(0, 2)
			total_size = origindev.tell() / 4096
		finally:
			origindev.close()
	finally:
		remoteserver.close()

	if not opts.quiet: print "Transferred %d of %d chunks (%d bytes per chunk)" % (xfer_count, total_size, chunksize)
	if not opts.quiet: print "You saved %f%% of your transfer size!" % ((total_size - xfer_count) / float(total_size) * 100, )

def run_apply(opts):
	snapfile = opts.snapfile
	device = opts.device

	snapfd = open(snapfile, 'r')
	try:
		handshake = snapfd.readline().strip()
		if handshake != PROTOCOL_VERSION:
			print >> sys.stderr, "Handshake failed; protocol mismatch? (saw '%s' expected '%s'" % (handshake, PROTOCOL_VERSION)
			sys.exit(1)

		process_dumpdata(snapfd, device, None)
	finally:
		snapfd.close()


# Call dmsetup ls and turn that into a hash of dm_name => [maj, min] data.
# Note that maj, min will be integers, and dm_name a string.
def read_dm_list():
	dmlist = {}
	for l in commands.getoutput('dmsetup ls').split('\n'):
		m = re.search('^(\S+)\s+\((\d+)(, |:)(\d+)\)$', l)
		if not m:
			continue
		dmlist[m.group(1)] = ( int(m.group(2)), int(m.group(4)) )
	return dmlist

# Call dmsetup table and turn that into a complicated hash of dm table data.
#
# Structure is:
#
#   dm_name => [
#     { :offset => int,
#       :length => int,
#       :type => (linear|snapshot|...),
#       :args => [str, str, str]
#     },
#     { ... }
#   ],
#   dm_name => [ ... ]
#
# The arguments are kept as a list of strings (split on whitespace), and
# you'll need to interpret them yourself.  Turning this whole shebang into a
# class hierarchy is a task for another time.
#
def read_dm_table():
	dmtable = {}
	for l in commands.getoutput('dmsetup table').split('\n'):
		m = re.search('^(\S+): (\d+) (\d+) (\S+) (.*)$', l)
		if not m:
			continue
		if not m.group(1) in dmtable:
			dmtable[m.group(1)] = []
		dmtable[m.group(1)].append( { 'offset': m.group(2),
		                 'length': m.group(3),
		                 'type': m.group(4),
		                 'args': re.split('\s+', m.group(5))
		               } )
	return dmtable

# Take a device name in any number of different formats and turn it into a
# "canonical" devicemapper name, equivalent to what you'll find in the likes
# of dmsetup ls
def canonicalise_dm(origname):
	m = re.search('^/dev/mapper/(.+)$', origname) 
	if m:
		return m.group(1)
	m = re.search('^/dev/([^/]+)/(.+)$', origname) 
	if m:
		vg = m.group(1)
		lv = m.group(2)
		return vg.replace('-','--') + \
		'-' + \
		lv.replace('-','--')
	m = re.search('^([^/]+)/(.*)$', origname) 
	if m:
		vg = m.group(1)
		lv = m.group(2)
		return vg.replace('-','--') + \
		'-' + \
		lv.replace('-','--')

	# Let's *assume* that the user just gave us vg-lv...
	return origname

# Find the name of a dm device that corresponds to the given <maj>:<min>
# string provided.
def dm_from_devnum(devnum, dmlist):
	(maj, min) = devnum.split(':', 2)
	for key in dmlist: 
		if dmlist[key] == (int(maj), int(min)): return key

# Read the header off our snapshot device, validate all is well, and return
# the chunksize used by the snapshot, in bytes
def read_header(snapdev):
	(magic, valid, metadata_version, chunksize) = struct.unpack("<LLLL", snapdev.read(16))
	if magic != 0x70416e53: raise RuntimeError("Invalid snapshot magic number")
	if valid != 1: raise RuntimeError("Snapshot marked as invalid")
	if metadata_version != 1: raise RuntimeError("Incompatible metadata version")

	# With all that out of the way, we can get down to business
	return chunksize * 512

# Are we on a big-endian system?  Needed for our htonq/ntohq methods
def big_endian():
	return struct.pack("h", 1) == struct.pack(">h", 1)

def htonq(val):
	if  big_endian(): 
		return struct.unpack("Q", struct.pack("Q", val)[::-1])[0] 
	else: 
		return val

def ntohq(val):
	return htonq (val)

if __name__ == "__main__": main()

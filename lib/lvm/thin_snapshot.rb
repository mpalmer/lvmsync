require 'rexml/document'

module LVM; end

class LVM::ThinSnapshot
	def initialize(vg, lv)
		@vg = vg
		@lv = lv
	end

	# Return an array of ranges which are the bytes which are different
	# between the origin and the snapshot.
	def differences
		# This is a relatively complicated multi-step process.  We have two
		# piles of <lv block> => <pool block> mappings, one for the "origin"
		# (the LV that's changing) and one for the "snapshot" (the LV that
		# represents some past point-in-time).  What we need to get out at the
		# end is an array of (<first byte>..<last byte>) ranges which cover
		# the parts of the volumes which are different (or that at least point
		# to different blocks within the data pool).
		#
		# This is going to take a few steps to accomplish.
		#
		# First, we translate each of the hashes into a list of two-element
		# arrays, expanding out ranges, because it means we don't have to
		# handle ranges differently in later steps (a worthwhile optimisation,
		# in my opinion -- if you think differently, I'd *really* welcome a
		# patch that handles ranges in-place without turning into a complete
		# mind-fuck, because I couldn't manage it).
		#
		# Next, we work out which mappings are "different" in all the possible
		# ways.  There's four cases we might come across:
		#
		# 1. Both origin and snapshot map the same LV block to the same data
		#    block.  This is a mapping we can discard from the set of
		#    differences, because, well, it isn't a difference.
		#
		# 2. Both origin and snapshot map the same LV block, but they point
		#    to different data blocks.  That's the easiest sort of difference
		#    to understand, and we *could* catch that just by comparing all
		#    of the mappings in the origin with the mappings in the snapshot,
		#    and listing those whose value differs.  But that wouldn't catch
		#    these next two cases...
		#
		# 3. The origin maps a particular LV block to a data block, but the
		#    snapshot doesn't have any mapping for that LV block.  This would
		#    occur quite commonly -- whenever a location in the origin LV was
		#    written to for the first time after the snapshot is taken.  You
		#    would catch all these (as well as the previous case) by taking
		#    the origin block map and removing any mappings which were
		#    identical in the snapshot block map.  However, that would fail to
		#    identify...
		#
		# 4. A block in the snapshot is mapped, when the corresponding origin
		#    block is *not* mapped.  Given the assumption that the snapshot
		#    was never written to, how could this possibly happen?  One word:
		#    "discard".  Mappings in the origin block list are removed if
		#    the block to which they refer is discarded.  Finding *these* (and also
		#    all mappings of type 2) by the reverse process to that in case
		#    3 -- simply remove from the snapshot block list all mappings which
		#    appear identically in the origin block list.
		#
		# In order to get all of 2, 3, and 4 together, we can simply do the
		# operations described in steps 3 & 4 and add the results together.  Sure,
		# we'll get two copies of all "type 2" block maps, but #uniq is good at
		# fixing that.
		#
		@differences ||= begin
			diff_maps = ((flat_origin_blocklist - flat_snapshot_blocklist) +
							 (flat_snapshot_blocklist - flat_origin_blocklist)
							).uniq

			# At this point, we're off to a good start -- we've got the mappings
			# that are different.  But we're not actually interested in the
			# mappings themselves -- all we want is "the list of LV blocks which
			# are different" (we'll translate LV blocks into byte ranges next).
			#
			changed_blocks = diff_maps.map { |m| m[0] }.uniq

			# Block-to-byte-range is pretty trivial, and we're done!
			changed_blocks.map do |b|
				((b*chunk_size)..(((b+1)*chunk_size)-1))
			end

			# There is one optimisation we could make here that we haven't --
			# coalescing adjacent byte ranges into single larger ranges.  I haven't
			# done it for two reasons: Firstly, I don't have any idea how much of a
			# real-world benefit it would be, and secondly, I couldn't work out how
			# to do it elegantly.  So I punted.
		end
	end

	def origin
		@origin ||= vgcfg.logical_volumes[@lv].origin
	end

	private
	def vgcfg
		@vgcfg ||= LVM::VGConfig.new(@vg)
	end

	def flat_origin_blocklist
		@flat_origin_blocklist ||= flatten_blocklist(origin_blocklist)
	end

	def flat_snapshot_blocklist
		@flat_snapshot_blocklist ||= flatten_blocklist(snapshot_blocklist)
	end

	def origin_blocklist
		@origin_blocklist ||= vg_block_dump[@vgcfg.logical_volumes[origin].device_id]
	end

	def snapshot_blocklist
		@snapshot_blocklist ||= vg_block_dump[@vgcfg.logical_volumes[@lv].device_id]
	end

	def thin_pool_name
		@thin_pool_name ||= vgcfg.logical_volumes[@lv].thin_pool
	end

	def thin_pool
		@thin_pool ||= vgcfg.logical_volumes[thin_pool_name]
	end

	def chunk_size
		@chunk_size ||= thin_pool.chunk_size
	end

	# Take a hash of <block-or-range> => <block-or-range> elements and turn
	# it into an array of [block, block] pairs -- any <range> => <range>
	# elements get expanded out into their constituent <block> => <block>
	# parts.
	#
	def flatten_blocklist(bl)
		bl.to_a.map do |elem|
			# Ranges are *hard*, let's go shopping
			if elem[0].is_a? Range
				lv_blocks = elem[0].to_a
				data_blocks = elem[1].to_a

				# This will now produce an array of two-element arrays, which
				# will itself be inside the top-level array that we're mapping.
				# A flatten(1) at the end will take care of that problem,
				# though.
				lv_blocks.inject([]) { |a, v| a << [v, data_blocks[a.length]] }
			elsif elem[0].is_a? Fixnum
				# We wrap the [lv, data] pair that is `elem` into another array,
				# so that the coming #flatten call doesn't de-array our matched
				# pair
				[elem]
			else
				raise ArgumentError,
				      "CAN'T HAPPEN: Unknown key type (#{elem.class}) found in blocklist"
			end
		end.flatten(1)
	end

	def vg_block_dump
		@vg_block_dump ||= begin
			doc = REXML::Document.new(`thin_dump /dev/mapper/#{@vg.gsub('-', '--')}-#{thin_pool_name.gsub('-','--')}_tmeta`)

			doc.elements['superblock'].inject({}) do |h, dev|
				next h unless dev.node_type == :element

				maps = dev.elements[''].inject({}) do |h2, r|
					next h2 unless r.node_type == :element

					if r.name == 'single_mapping'
						h2[r.attribute('origin_block').value.to_i] = r.attribute('data_block').value.to_i
					else
						len = r.attribute('length').value.to_i
						ori = r.attribute('origin_begin').value.to_i
						dat = r.attribute('data_begin').value.to_i
						h2[(ori..ori+len-1)] = (dat..dat+len-1)
					end

					h2
				end

				h[dev.attribute('dev_id').value.to_i] = maps
				h
			end
		end
	end
end

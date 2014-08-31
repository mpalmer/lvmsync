require 'rexml/document'
require 'lvm/helpers'

module LVM; end

class LVM::Snapshot
	include LVM::Helpers

	def initialize(vg, lv)
		@vg = vg
		@lv = lv
	end

	# Return an array of ranges which are the bytes which are different
	# between the origin and the snapshot.
	def differences
		@differences ||= begin
			# For a regular, old-skool snapshot, getting the differences is
			# pretty trivial -- just read through the snapshot metadata, and
			# the list of changed blocks is right there.
			#
			diff_block_list = []

			File.open(metadata_device, 'r') do |metafd|
				in_progress = true

				# The first chunk of the metadata LV is the header, which we
				# don't care for at all
				metafd.seek chunk_size, IO::SEEK_SET

				while in_progress
					# The snapshot on-disk format is a stream of <blocklist>, <blockdata>
					# sets; within each <blocklist>, it's network-byte-order 64-bit block
					# IDs -- the first is the location (chunk_size * offset) in the origin
					# LV that the data has been changed, the second is the location (again,
					# chunk_size * offset) in the metadata LV where the changed data is
					# being stored.
					(chunk_size / 16).times do
						origin_offset, snap_offset = metafd.read(16).unpack("QQ")
						origin_offset = ntohq(origin_offset)
						snap_offset   = ntohq(snap_offset)

						# A snapshot offset of 0 would point back to the metadata
						# device header, so that's clearly invalid -- hence it's the
						# "no more blocks" indicator.
						if snap_offset == 0
							in_progress = false
							break
						end

						diff_block_list << origin_offset
					end

					# We've read through a set of origin => data mappings; now we need
					# to take a giant leap over the data blocks that follow it.
					metafd.seek chunk_size * chunk_size / 16, IO::SEEK_CUR
				end
			end

			# Block-to-byte-range is pretty trivial, and we're done!
			diff_block_list.map do |b|
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
		# Man old-skool snapshots are weird
		vgcfg.logical_volumes.values.find { |lv| lv.cow_store == @lv }.origin
	end

	private
	def vgcfg
		@vgcfg ||= LVM::VGConfig.new(@vg)
	end

	def chunk_size
		@chunk_size ||= metadata_header[:chunk_size]
	end

	def metadata_header
		@metadata_header ||= begin
			magic, valid, version, chunk_size = File.read(metadata_device, 16).unpack("VVVV")

			unless magic == 0x70416e53
				raise RuntimeError,
				      "#{@vg}/#{@lv}: Invalid snapshot magic number"
			end

			unless valid == 1
				raise RuntimeError,
				      "#{@vg}/#{@lv}: Snapshot is marked as invalid"
			end

			unless version == 1
				raise RuntimeError,
				      "#{@vg}/#{@lv}: Incompatible snapshot metadata version"
			end

			{ :chunk_size => chunk_size * 512 }
		end
	end

	def metadata_device
		"/dev/mapper/#{@vg.gsub('-', '--')}-#{@lv.gsub('-', '--')}-cow"
	end
end

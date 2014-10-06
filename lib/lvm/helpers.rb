module LVM; end

module LVM::Helpers
	# Are we on a big-endian system?  Needed for our htonq/ntohq methods
	def big_endian?
		@big_endian ||= [1].pack("s") == [1].pack("n")
	end

	def htonq val
		# This won't work on a nUxi byte-order machine, but if you have one of
		# those, I'm guessing you've got bigger problems
		big_endian? ? val : swap_longs(val)
	end

	def ntohq val
		big_endian? ? val : swap_longs(val)
	end

	# On-disk (LVM) format (which is little-endian) to host byte order
	def dtohq val
		big_endian? ? swap_longs(val) : val
	end

	def swap_longs val
		[val].pack("Q").reverse.unpack("Q").first
	end
end

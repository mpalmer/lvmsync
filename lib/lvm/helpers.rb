module LVM; end

module LVM::Helpers
	# Are we on a big-endian system?  Needed for our htonq/ntohq methods
	def big_endian?
		@bigendian ||= [1].pack("s") == [1].pack("n")
	end

	def htonq val
		# This won't work on a nUxi byte-order machine, but if you have one of
		# those, I'm guessing you've got bigger problems
		big_endian? ? ([val].pack("Q").reverse.unpack("Q").first) : val
	end

	def ntohq val
		htonq val
	end
end

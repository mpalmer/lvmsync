module LVM; end

# This class represents an LVM logical volume, in all its glory.  You can
# perform various operations on it.
class LVM::LogicalVolume
	# Create a new instance of LVM::LogicalVolume.
	#
	# New instances can be created in one of two ways:
	#
	#  * Pass a single argument, containing any path which LVM can resolve to
	#    a logical volume.  Typically, this will either be `/dev/<vg>/<lv>`
	#    or `/dev/mapper/<vg>-<lv>`, but we don't try to parse it ourselves,
	#    relying instead on `lvs` to do the heavy lifting.
	#
	#  * Pass two arguments, which are the volume group name and logical
	#    volume name, respectively.
	#
	# This method will raise `RuntimeError` if the path specified can't be
	# resolved to an LV, or if the specified VG name or LV name don't resolve
	# to an active logical volume.
	#
	def initialize(path_or_vg_name, lv_name=nil)
		if lv_name.nil?
			path = path_or_vg_name
			@vg_name, @lv_name = `lvs --noheadings -o vg_name,lv_name #{path} 2>/dev/null`.strip.split(/\s+/, 2)
			if $?.exitstatus != 0
				raise RuntimeError,
				      "Failed to interrogate LVM about '#{path}'.  Perhaps you misspelt it?"
			end
		else
			@vg_name = path_or_vg_name
			@lv_name = lv_name
		end

		@vgcfg = LVM::VGConfig.new(@vg_name)
		@lvcfg = @vgcfg.logical_volumes[@lv_name]

		if @lvcfg.nil?
			raise RuntimeError,
			      "Logical volume #{@lv_name} does not exist in volume group #{@vg_name}"
		end
	end

	# Return a string containing a canonical path to the block device
	# representing this LV.
	def path
		"/dev/mapper/#{@vg_name.gsub('-', '--')}-#{@lv_name.gsub('-', '--')}"
	end

	# Is this LV a snapshot?
	def snapshot?
		@lvcfg.snapshot?
	end

	# Return an LVM::LogicalVolume object which is the origin volume of
	# this one (if this LV is a snapshot), or `nil` otherwise.
	def origin
		return nil unless snapshot?

		if @lvcfg.origin
			LVM::LogicalVolume.new(@vg_name, @lvcfg.origin)
		else
			origin_lv_name = @vgcfg.logical_volumes.values.find { |lv| lv.cow_store == @lv_name }.origin
			LVM::LogicalVolume.new(@vg_name, origin_lv_name)
		end
	end

	# Return an array of ranges, each of which represents an inclusive range
	# of bytes which are different between this logical volume and its
	# origin.
	#
	# If this LV is not a snapshot, this method returns an empty array.
	#
	def changes
		return [] unless snapshot?

		if @lvcfg.thin?
			LVM::ThinSnapshot.new(@vg_name, @lv_name)
		else
			LVM::Snapshot.new(@vg_name, @lv_name)
		end.differences
	end
end

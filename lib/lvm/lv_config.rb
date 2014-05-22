module LVM; end

class LVM::LVConfig
	attr_reader :name

	def initialize(tree, name, vgcfg)
		@root = tree
		@name = name
		@vgcfg = vgcfg
	end

	def thin?
		@root.groups['segment1'].variable_value('type') == 'thin'
	end

	def snapshot?
		thin? ? !origin.nil? : !@vgcfg.logical_volumes.values.find { |lv| lv.cow_store == name }.nil?
	end

	def thin_pool
		@root.groups['segment1'].variable_value('thin_pool')
	end

	def device_id
		@root.groups['segment1'].variable_value('device_id')
	end

	def origin
		@root.groups['segment1'].variable_value('origin')
	end

	def cow_store
		@root.groups['segment1'].variable_value('cow_store')
	end

	def chunk_size
		@root.groups['segment1'].variable_value('chunk_size') * 512
	end
end

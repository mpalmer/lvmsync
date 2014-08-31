require 'tempfile'
require 'open3'
require 'treetop'
require File.expand_path('../../vgcfgbackup', __FILE__)

Treetop.load(File.expand_path('../../vgcfgbackup.treetop', __FILE__))

require 'lvm/lv_config'
require 'lvm/pv_config'
require 'lvm/snapshot'
require 'lvm/thin_snapshot'

module LVM; end

class LVM::VGConfig
	def initialize(vg_name, opts = {})
		@vgcfgbackup_cmd = opts[:vgcfgbackup_command] || 'vgcfgbackup'
		@vg_name = vg_name
		@parser = VgCfgBackupParser.new
		@root = @parser.parse(vgcfgbackup_output)
		if @root.nil?
			raise RuntimeError,
			      "Cannot parse vgcfgbackup output: #{@parser.failure_reason}"
		end
	end

	def version
		@version ||= @root.variable_value('version')
	end

	def description
		@description ||= @root.variable_value('description')
	end

	def uuid
		@uuid ||= volume_group.variable_value('id')
	end

	def volume_group
		@volume_group ||= @root.groups[@vg_name]
	end

	def physical_volumes
		@physical_volumes ||= volume_group.groups['physical_volumes'].groups.to_a.inject({}) { |h,v| h[v[0]] = LVM::PVConfig.new(v[1]); h }
	end

	def logical_volumes
		@logical_volumes ||= volume_group.groups['logical_volumes'].groups.to_a.inject({}) { |h,v| h[v[0]] = LVM::LVConfig.new(v[1], v[0], self); h }
	end

	private
	def vgcfgbackup_output
		@vgcfgbackup_output ||= begin
			out = nil

			Tempfile.open('vg_config') do |tmpf|
				cmd = "#{@vgcfgbackup_cmd} -f #{tmpf.path} #{@vg_name}"
				stdout = nil
				stderr = nil
				exit_status = nil

				Open3.popen3(cmd) do |stdin_fd, stdout_fd, stderr_fd, wait_thr|
					stdin_fd.close
					stdout = stdout_fd.read
					stderr = stderr_fd.read
					exit_status = wait_thr.value if wait_thr
				end

				if (exit_status or $?).exitstatus != 0
					raise RuntimeError,
					      "Failed to run vgcfgbackup: #{stdout}\n#{stderr}"
				end

				out = File.read(tmpf.path)
			end

			out
		end
	end
end

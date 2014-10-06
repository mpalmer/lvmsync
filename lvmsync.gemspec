require 'git-version-bump'

Gem::Specification.new do |s|
	s.name = "lvmsync"

	s.version = GVB.version
	s.date    = GVB.date

	s.platform = Gem::Platform::RUBY

	s.homepage = "http://theshed.hezmatt.org/lvmsync"
	s.summary = "Efficiently transfer changes in LVM snapshots"
	s.authors = ["Matt Palmer"]

	s.extra_rdoc_files = ["README.md"]
	s.files = %w{
		README.md
		LICENCE
		bin/lvmsync
		lib/lvm.rb
		lib/lvm/lv_config.rb
		lib/lvm/thin_snapshot.rb
		lib/lvm/snapshot.rb
		lib/lvm/vg_config.rb
		lib/lvm/helpers.rb
		lib/lvm/pv_config.rb
		lib/vgcfgbackup.treetop
		lib/vgcfgbackup.rb
	}
	s.executables = ["lvmsync"]

	s.add_runtime_dependency "git-version-bump"
	s.add_runtime_dependency "treetop"

	s.add_development_dependency 'bundler'
	s.add_development_dependency 'github-release'
	s.add_development_dependency 'guard-spork'
	s.add_development_dependency 'guard-rspec'
	s.add_development_dependency 'plymouth'
	s.add_development_dependency 'pry-debugger'
	s.add_development_dependency 'rake'
	# Needed for guard
	s.add_development_dependency 'rb-inotify', '~> 0.9'
	s.add_development_dependency 'rdoc'
	s.add_development_dependency 'rspec'
end

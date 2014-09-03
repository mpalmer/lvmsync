require 'rubygems'
require 'bundler'

begin
	Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
	$stderr.puts e.message
	$stderr.puts "Run `bundle install` to install missing gems"
	exit e.status_code
end

require 'git-version-bump/rake-tasks'

Bundler::GemHelper.install_tasks

task :release do
	sh "git release"
end

require 'rdoc/task'

Rake::RDocTask.new do |rd|
	rd.main = "README.md"
	rd.title = 'lvmsync'
	rd.rdoc_files.include("README.md", "lib/**/*.rb")
end

desc "Run guard"
task :guard do
	require 'guard'
	::Guard.start(:clear => true)
	while ::Guard.running do
		sleep 0.5
	end
end

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new :test do |t|
	t.pattern = "spec/**/*_spec.rb"
end

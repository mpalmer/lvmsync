require 'spork'

Spork.prefork do
	require 'bundler'
	Bundler.setup(:default, :test)
	require 'rspec/core'

	require 'rspec/mocks'

	require 'pry'
	require 'plymouth'

	RSpec.configure do |config|
		config.fail_fast = true
#		config.full_backtrace = true

		config.expect_with :rspec do |c|
			c.syntax = :expect
		end
	end
end

Spork.each_run do
	# Nothing to do here, specs will load the files they need
end

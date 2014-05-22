guard 'spork' do
  watch('Gemfile')             { :rspec }
  watch('Gemfile.lock')        { :rspec }
  watch('spec/spec_helper.rb') { :rspec }
end

guard 'rspec',
      :cmd          => "rspec --drb",
      :all_on_start => true do
  watch(%r{^spec/.+_spec\.rb$})
  watch(%r{^lib/})               { "spec" }
end


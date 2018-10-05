source ENV['GEM_SOURCE'] || 'https://rubygems.org'

puppetversion = ENV.key?('PUPPET_VERSION') ? ENV['PUPPET_VERSION'] : ['>= 3.3']

gem 'facter', '>= 1.7.0'
gem 'metadata-json-lint'
gem 'puppet', puppetversion
gem 'rake'
gem 'rubocop'
gem 'vault'
gem 'debouncer'

# # rspec must be v2 for ruby 1.8.7
# if RUBY_VERSION >= '1.8.7' && RUBY_VERSION < '1.9'
#   gem 'rspec', '~> 2.0'
#   gem 'rake', '~> 10.0'
# else
#   # rubocop requires ruby >= 1.9
#   gem 'rubocop'
# end

group :development do
  gem 'puppet-lint', '>= 1.0.0'
  gem 'ruby-debug-ide'
end

group :test do
  gem 'puppetlabs_spec_helper', '>= 1.2.0'

  gem 'rspec'
  gem 'rspec-puppet'
  gem 'rspec-puppet-utils'

  gem 'simplecov'
  gem 'simplecov-console'
end


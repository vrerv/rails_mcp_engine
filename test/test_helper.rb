# Configure Rails Environment
ENV['RAILS_ENV'] = 'test'

require_relative '../manual_app/config/environment'
require 'rails/test_help'

# Filter out Minitest backtrace while allowing backtrace from other libraries
# to be shown.
Minitest.backtrace_filter = Minitest::BacktraceFilter.new

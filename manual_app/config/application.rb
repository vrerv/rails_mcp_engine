# frozen_string_literal: true

require_relative 'boot'
require 'rails'
require 'action_controller/railtie'
require 'active_support/core_ext/integer/time'
require 'pathname'

Bundler.require(*Rails.groups)

module ManualApp
  class Application < Rails::Application
    config.load_defaults 7.1
    config.time_zone = 'UTC'

    config.autoload_paths << Rails.root.join('lib')

    engine_root = Pathname.new(__dir__).join('..', '..').expand_path
    config.autoload_paths << engine_root.join('app/lib')
    config.autoload_paths << engine_root.join('app/services')
    config.eager_load_paths << engine_root.join('app/lib')
    config.eager_load_paths << engine_root.join('app/services')

    config.action_controller.include_all_helpers = false
  end
end

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

    config.action_controller.include_all_helpers = false
    config.hosts << ENV['DEFAULT_DOMAIN'] if ENV['DEFAULT_DOMAIN'].present?
  end
end

require 'rails'
require 'ruby_llm'
require 'fast_mcp'

module RailsMcpEngine
  class Engine < ::Rails::Engine
    # Define the base class expected by the engine, inheriting from the real gem
    # This ensures ApplicationTool is available to the host app and the engine
    initializer 'rails_mcp_engine.define_base_class' do
      unless defined?(::ApplicationTool)
        class ::ApplicationTool < FastMcp::Tool
        end
      end
    end

    # Add engine directories to LOAD_PATH so internal requires work
    config.before_configuration do
      $LOAD_PATH.unshift root.join('app/lib').to_s
      $LOAD_PATH.unshift root.join('app/services').to_s
    end

    # Trigger tool generation on boot and reload
    config.to_prepare do
      RailsMcpEngine::Engine.build_tools!
    end

    def self.build_tools!
      # Ensure all services are loaded so they register in ToolMeta
      # This is critical for development mode where autoloading is lazy
      # and for test mode where eager_load is false
      Rails.application.eager_load! unless Rails.application.config.eager_load

      ToolMeta.registry.each do |service_class|
        schema = ToolSchema::Builder.build(service_class)
        ToolSchema::RubyLlmFactory.build(service_class, schema)
        ToolSchema::FastMcpFactory.build(service_class, schema)
      end
    end
  end
end

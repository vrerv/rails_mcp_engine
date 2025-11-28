# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'fast_mcp_builder'

module ToolSchema
  class FastMcpFactory
    extend T::Sig

    sig { params(service_class: T.class_of(Object), schema: T::Hash[Symbol, T.untyped]).returns(T.class_of(Object)) }
    def self.build(service_class, schema)
      tool_constant = tool_class_name(service_class)
      parent = Mcp
      parent.send(:remove_const, tool_constant) if parent.const_defined?(tool_constant, false)

      klass = Class.new(ApplicationTool) do
        description(schema[:description])
        arguments(&FastMcpBuilder.arguments_block(schema[:params]))

        define_method(:call) do |**kwargs|
          service_class.new.public_send(schema[:entrypoint], **kwargs)
        end
      end

      parent.const_set(tool_constant, klass)
    end

    sig { params(service_class: T.class_of(Object)).returns(String) }
    def self.tool_class_name(service_class)
      base = service_class.name.split('::').last
      base.gsub(/Service$/, '')
    end
  end
end

module Mcp
end

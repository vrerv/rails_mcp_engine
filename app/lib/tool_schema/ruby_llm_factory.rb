# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'ruby_llm_builder'

module ToolSchema
  class RubyLlmFactory
    extend T::Sig

    sig do
      params(
        service_class: T.class_of(Object),
        schema: T::Hash[Symbol, T.untyped],
        before_call: T.nilable(Proc),
        after_call: T.nilable(Proc)
      ).returns(T.class_of(Object))
    end
    def self.build(service_class, schema, before_call: nil, after_call: nil)
      tool_constant = tool_class_name(service_class)
      parent = Tools
      parent.send(:remove_const, tool_constant) if parent.const_defined?(tool_constant, false)

      klass = Class.new(RubyLLM::Tool) do
        description(schema[:description])
        params(&RubyLlmBuilder.params_block(schema[:params]))

        define_method(:execute) do |**kwargs|
          before_call&.call(kwargs)
          result = service_class.new.public_send(schema[:entrypoint], **kwargs)
          after_call&.call(result)
          result
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

module Tools
end

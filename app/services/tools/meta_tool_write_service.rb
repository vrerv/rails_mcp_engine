# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'tool_meta'
require 'tool_schema/builder'
require 'tool_schema/ruby_llm_factory'
require 'tool_schema/fast_mcp_factory'

module Tools
  class MetaToolWriteService
    extend T::Sig

    sig { params(class_name: T.nilable(String), source: T.nilable(String), before_call: T.nilable(Proc), after_call: T.nilable(Proc)).returns(T::Hash[Symbol, T.untyped]) }
    def register_tool(class_name, source: nil, before_call: nil, after_call: nil)
      return { error: 'class_name is required for register' } if class_name.nil? || class_name.empty?

      # If source is provided, evaluate it first
      if source
        begin
          Object.class_eval(source)
        rescue StandardError => e
          return { error: "Failed to evaluate source: #{e.message}" }
        end
      end

      begin
        service_class = meta_service.constantize(class_name)
      rescue NameError
        return { error: "Could not find #{class_name}" }
      end
      
      return { error: "#{class_name} must extend ToolMeta" } unless service_class.respond_to?(:tool_metadata)

      ToolMeta.registry << service_class unless ToolMeta.registry.include?(service_class)

      schema = ToolSchema::Builder.build(service_class)
      ToolSchema::RubyLlmFactory.build(service_class, schema, before_call: before_call, after_call: after_call)
      ToolSchema::FastMcpFactory.build(service_class, schema, before_call: before_call, after_call: after_call)

      { status: 'registered', tool: meta_service.summary_payload(schema) }
    rescue ToolMeta::MissingSignatureError => e
      { error: e.message }
    rescue NameError => e
      { error: "Could not find #{class_name}: #{e.message}" }
    end

    sig { params(tool_name: String).returns(T::Hash[Symbol, T.untyped]) }
    def delete_tool(tool_name)
      schema = meta_service.find_schema(tool_name)
      return { error: "Tool not found: #{tool_name}" } unless schema

      service_class = schema[:service_class]
      ToolMeta.registry.delete(service_class)

      tool_constant = ToolSchema::RubyLlmFactory.tool_class_name(service_class)
      Tools.send(:remove_const, tool_constant) if Tools.const_defined?(tool_constant, false)
      fast_mcp_constant = ToolSchema::FastMcpFactory.tool_class_name(service_class)
      Mcp.send(:remove_const, fast_mcp_constant) if Mcp.const_defined?(fast_mcp_constant, false)

      { success: 'Tool deleted successfully' }
    rescue StandardError => e
      { error: e.message }
    end

    private

    def meta_service
      @meta_service ||= Tools::MetaToolService.new
    end
  end
end

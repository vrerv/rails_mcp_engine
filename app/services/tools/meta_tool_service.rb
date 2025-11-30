# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'tool_meta'
require 'tool_schema/builder'
require 'tool_schema/ruby_llm_factory'
require 'tool_schema/fast_mcp_factory'

module Tools
  class MetaToolService
    extend T::Sig
    extend ToolMeta

    tool_name 'meta_tool'
    tool_description 'Inspect and run registered tools via a single meta interface.'
    tool_param :action, description: 'Operation to perform', enum: %w[search list list_summary get run]
    tool_param :tool_name, description: 'Tool name to target (for get/run)', required: false
    tool_param :query, description: 'Search string to match against tool names/descriptions', required: false
    tool_param :arguments, description: 'Arguments to pass when running a tool', required: false

    sig do
      params(
        action: String,
        tool_name: T.nilable(String),
        query: T.nilable(String),
        arguments: T.nilable(T::Hash[T.untyped, T.untyped])
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def call(action:, tool_name: nil, query: nil, arguments: nil)
      case action
      when 'search'
        search_tools(query)
      when 'list'
        { tools: list_tools }
      when 'list_summary'
        { tools: list_summaries }
      when 'get'
        get_tool(tool_name)
      when 'run'
        run_tool(tool_name, arguments || {})
      else
        { error: "Unknown action: #{action}" }
      end
    end

    sig { params(class_name: T.nilable(String), before_call: T.nilable(Proc), after_call: T.nilable(Proc)).returns(T::Hash[Symbol, T.untyped]) }
    def register_tool(class_name, before_call: nil, after_call: nil)
      return { error: 'class_name is required for register' } if class_name.nil? || class_name.empty?

      service_class = constantize(class_name)
      return { error: "Could not find #{class_name}" } if service_class.nil?
      return { error: "#{class_name} must extend ToolMeta" } unless service_class.respond_to?(:tool_metadata)

      ToolMeta.registry << service_class unless ToolMeta.registry.include?(service_class)

      schema = ToolSchema::Builder.build(service_class)
      ToolSchema::RubyLlmFactory.build(service_class, schema, before_call: before_call, after_call: after_call)
      ToolSchema::FastMcpFactory.build(service_class, schema, before_call: before_call, after_call: after_call)

      { status: 'registered', tool: summary_payload(schema) }
    rescue ToolMeta::MissingSignatureError => e
      { error: e.message }
    end

    private

    sig { params(query: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
    def search_tools(query)
      return { tools: list_tools } if query.nil? || query.empty?

      normalized = query.downcase
      tools = list_tools.select do |tool|
        tool[:name].downcase.include?(normalized) || tool[:description].downcase.include?(normalized)
      end

      { tools: tools }
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def list_tools
      schemas.map { |schema| detailed_payload(schema) }
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def list_summaries
      schemas.map { |schema| summary_payload(schema) }
    end

    sig { params(tool_name: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
    def get_tool(tool_name)
      schema = find_schema(tool_name)
      return { error: "Tool not found: #{tool_name}" } unless schema

      { tool: detailed_payload(schema) }
    end

    sig { params(tool_name: T.nilable(String), arguments: T::Hash[T.untyped, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def run_tool(tool_name, arguments)
      schema = find_schema(tool_name)
      return { error: "Tool not found: #{tool_name}" } unless schema

      service_class = schema[:service_class]
      result = service_class.new.public_send(schema[:entrypoint], **deep_symbolize(arguments))

      { tool: summary_payload(schema), result: result }
    rescue ArgumentError => e
      { error: e.message }
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def schemas
      ToolMeta.registry.map { |service_class| ToolSchema::Builder.build(service_class) }
    end

    sig { params(tool_name: T.nilable(String)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def find_schema(tool_name)
      return nil if tool_name.nil? || tool_name.empty?

      schemas.find { |schema| schema[:name] == tool_name }
    end

    sig { params(schema: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def summary_payload(schema)
      {
        name: schema[:name],
        description: schema[:description],
        usage: usage_string(schema)
      }
    end

    sig { params(schema: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def detailed_payload(schema)
      summary_payload(schema).merge(params: schema[:params], return_type: schema[:return_type])
    end

    sig { params(schema: T::Hash[Symbol, T.untyped]).returns(String) }
    def usage_string(schema)
      param_list = schema[:params].map { |param| param[:name].to_s }.join(', ')
      "#{schema[:name]}(#{param_list})"
    end

    sig { params(name: String).returns(T.class_of(Object)) }
    def constantize(name)
      Object.const_get(name)
    end

    sig { params(value: T.untyped).returns(T.untyped) }
    def deep_symbolize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), result|
          symbol_key = key.is_a?(String) ? key.to_sym : key
          result[symbol_key] = deep_symbolize(nested)
        end
      when Array
        value.map { |element| deep_symbolize(element) }
      else
        value
      end
    end
  end
end

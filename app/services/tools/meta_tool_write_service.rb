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

      { status: 'registered', tool: meta_service.summary_payload(schema) }
    rescue ToolMeta::MissingSignatureError => e
      { error: e.message }
    rescue NameError => e
      { error: "Could not find #{class_name}: #{e.message}" }
    end

    sig { params(source: T.nilable(String), before_call: T.nilable(Proc), after_call: T.nilable(Proc)).returns(T::Hash[Symbol, T.untyped]) }
    def register_tool_from_source(source: nil, before_call: nil, after_call: nil)
      class_name = extract_class_name(source)
      return { error: 'class_name is required for register' } if class_name.nil? || class_name.empty?

      # If source is provided, evaluate it first
      if source
        begin
          Object.class_eval(source)
        rescue StandardError => e
          return { error: "Failed to evaluate source: #{e.message}" }
        end
      end

      register_tool(class_name, before_call: before_call, after_call: after_call)
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

    def extract_class_name(source)
      require 'ripper'
      sexp = Ripper.sexp(source)
      return nil unless sexp

      # sexp is [:program, statements]
      statements = sexp[1]
      find_class(statements, [])
    end

    def find_class(statements, namespace)
      return nil unless statements.is_a?(Array)

      statements.each do |stmt|
        next unless stmt.is_a?(Array)

        case stmt.first
        when :module
          # [:module, const_ref, body]
          # body is [:bodystmt, statements, ...]
          const_node = stmt[1]
          const_name = get_const_name(const_node)

          body_stmt = stmt[2]
          inner_statements = body_stmt[1]

          result = find_class(inner_statements, namespace + [const_name])
          return result if result
        when :class
          # [:class, const_ref, superclass, body]
          const_node = stmt[1]
          const_name = get_const_name(const_node)

          return (namespace + [const_name]).join('::')
        end
      end
      nil
    end

    def get_const_name(node)
      return nil unless node.is_a?(Array)

      type = node.first
      if type == :const_ref
        # [:const_ref, [:@const, "Name", ...]]
        node[1][1]
      elsif type == :const_path_ref
        # [:const_path_ref, parent, child]
        parent = node[1]
        child = node[2] # [:@const, "Name", ...]

        parent_name = if parent.first == :var_ref
                        parent[1][1]
                      else
                        get_const_name(parent)
                      end

        "#{parent_name}::#{child[1]}"
      else
        nil
      end
    end

    def constantize(name)
      Object.const_get(name)
    end
  end
end

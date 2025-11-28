# frozen_string_literal: true

require 'json'

class ManualController < ApplicationController
  def show
    @register_result = flash[:register_result]
    @test_result = flash[:test_result]
    @tools = schemas
  end

  def register
    source = params[:source].to_s
    class_name = extract_class_name(source)

    result = if source.strip.empty?
               { error: 'Tool source code is required' }
             elsif class_name.nil?
               { error: 'Could not infer class name from the provided source' }
             else
               register_source(source, class_name)
             end

    flash[:register_result] = result
    redirect_to root_path
  end

  def run
    tool_name = params[:tool_name].to_s
    parsed_arguments = parse_arguments(params[:arguments])
    schema = schemas.find { |s| s[:name] == tool_name }

    result = if schema.nil?
               { error: "Tool not found: #{tool_name}" }
             elsif parsed_arguments.is_a?(String)
               { error: parsed_arguments }
             else
               invoke_tool(schema, parsed_arguments)
             end

    flash[:test_result] = result
    redirect_to root_path
  end

  def delete_tool
    tool_name = params[:tool_name].to_s
    schema = schemas.find { |s| s[:name] == tool_name }

    result = if schema.nil?
               { error: "Tool not found: #{tool_name}" }
             else
               delete_tool_from_registry(schema[:service_class])
             end

    flash[:register_result] = result
    redirect_to root_path
  end

  private

  def schemas
    ToolMeta.registry.map { |service_class| ToolSchema::Builder.build(service_class) }
  end

  def extract_class_name(source)
    source.match(/class\s+([A-Za-z0-9_:]+)/)&.captures&.first
  end

  def register_source(source, class_name)
    Object.class_eval(source)
    Tools::MetaToolService.new.register_tool(
      class_name,
      before_call: ->(args) { Rails.logger.info("  [MCP] Request #{class_name}: #{args.inspect}") },
      after_call: ->(result) { Rails.logger.info("  [MCP] Response #{class_name}: #{result.inspect}") }
    )
  rescue StandardError => e
    { error: e.message }
  end

  def parse_arguments(raw_value)
    return {} if raw_value.to_s.strip.empty?

    JSON.parse(raw_value, symbolize_names: true)
  rescue JSON::ParserError => e
    e.message
  end

  def invoke_tool(schema, arguments)
    tool_constant = ToolSchema::RubyLlmFactory.tool_class_name(schema[:service_class])
    tool_class = Tools.const_get(tool_constant)
    result = tool_class.new.execute(**arguments.symbolize_keys)

    { tool: { name: schema[:name], description: schema[:description] }, result: result }
  rescue StandardError => e
    { error: e.message }
  end

  def delete_tool_from_registry(service_class)
    ToolMeta.registry.delete(service_class)

    # Also remove the RubyLLM tool class constant
    tool_constant = ToolSchema::RubyLlmFactory.tool_class_name(service_class)
    Tools.send(:remove_const, tool_constant) if Tools.const_defined?(tool_constant, false)

    { success: 'Tool deleted successfully' }
  rescue StandardError => e
    { error: e.message }
  end
end

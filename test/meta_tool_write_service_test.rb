# frozen_string_literal: true

require 'test_helper'
require 'tools/meta_tool_write_service'

class MetaToolWriteServiceTest < Minitest::Test
  def setup
    ToolMeta.clear_registry
    remove_constants
    build_sample_service
  end

  def test_registers_service_and_builds_wrappers
    ToolMeta.clear_registry
    result = write_service.register_tool('Tools::SampleService')

    assert_equal 'registered', result[:status]
    assert_includes ToolMeta.registry, Tools::SampleService

    schema = ToolSchema::Builder.build(Tools::SampleService)
    ruby_tool = ToolSchema::RubyLlmFactory.build(Tools::SampleService, schema)
    fast_tool = ToolSchema::FastMcpFactory.build(Tools::SampleService, schema)

    assert_equal 'Say a friendly hello', ruby_tool.description(nil)
    assert_equal 'Say a friendly hello', fast_tool.description(nil)
    assert_equal 'sample', fast_tool.tool_name
  end

  def test_register_tool_with_hooks
    ToolMeta.clear_registry

    before_called = false
    after_called = false

    write_service.register_tool(
      'Tools::SampleService',
      before_call: ->(_args) { before_called = true },
      after_call: ->(_result) { after_called = true }
    )

    tool_class = Mcp::Sample
    tool_class.new.call(name: 'Hooks')

    assert before_called, 'Before hook should be called'
    assert after_called, 'After hook should be called'
  end

  def test_delete_tool
    write_service.register_tool('Tools::SampleService')
    assert_includes ToolMeta.registry, Tools::SampleService

    result = write_service.delete_tool('sample')
    assert_equal 'Tool deleted successfully', result[:success]
    refute_includes ToolMeta.registry, Tools::SampleService
    refute Tools.const_defined?(:Sample)
    refute Mcp.const_defined?(:Sample)
  end

  def test_delete_non_existent_tool
    result = write_service.delete_tool('non_existent')
    assert_equal 'Tool not found: non_existent', result[:error]
  end

  private

  def write_service
    Tools::MetaToolWriteService.new
  end

  def build_sample_service
    Tools.const_set(:SampleService, Class.new do
      extend T::Sig
      extend ToolMeta

      tool_name 'sample'
      tool_description 'Say a friendly hello'
      tool_param :name, description: 'Name to greet'

      sig { params(name: String).returns(String) }
      def call(name:)
        "Hello, #{name}!"
      end
    end)
  end

  def remove_constants
    Tools.send(:remove_const, :SampleService) if Tools.const_defined?(:SampleService, false)
    Tools.send(:remove_const, :Sample) if Tools.const_defined?(:Sample, false)
  end
end

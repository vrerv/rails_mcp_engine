# frozen_string_literal: true

require 'test_helper'
require 'tools/meta_tool_service'

class MetaToolServiceTest < Minitest::Test
  def setup
    ToolMeta.clear_registry
    remove_constants
    build_sample_service
  end

  def test_registers_service_and_builds_wrappers
    ToolMeta.clear_registry
    result = meta_service.register_tool('Tools::SampleService')

    assert_equal 'registered', result[:status]
    assert_includes ToolMeta.registry, Tools::SampleService

    schema = ToolSchema::Builder.build(Tools::SampleService)
    ruby_tool = ToolSchema::RubyLlmFactory.build(Tools::SampleService, schema)
    fast_tool = ToolSchema::FastMcpFactory.build(Tools::SampleService, schema)

    assert_equal 'Say a friendly hello', ruby_tool.description(nil)
    assert_equal 'Say a friendly hello', fast_tool.description(nil)
  end

  def test_lists_and_searches_tools
    list = meta_service.call(action: 'list', tool_name: nil, query: nil, arguments: nil)
    assert_equal 'sample', list[:tools].first[:name]

    summary = meta_service.call(action: 'list_summary', tool_name: nil, query: nil, arguments: nil)
    assert_equal 'sample', summary[:tools].first[:name]

    search = meta_service.call(action: 'search', query: 'hello', tool_name: nil, arguments: nil)
    assert_equal 'sample', search[:tools].first[:name]
  end

  def test_get_and_run_tool
    get_result = meta_service.call(action: 'get', tool_name: 'sample', query: nil, arguments: nil)
    assert_equal 'sample', get_result[:tool][:name]
    refute_empty get_result[:tool][:params]

    run_result = meta_service.call(action: 'run', tool_name: 'sample', query: nil, arguments: { name: 'Ada' })
    assert_equal 'Hello, Ada!', run_result[:result]
  end

  def test_run_tool_deep_symbolizes_nested_arguments
    build_nested_service

    arguments = {
      'payload' => {
        'user' => {
          'name' => 'Ada',
          'tags' => [{ 'label' => 'friend' }]
        }
      }
    }

    run_result = meta_service.call(action: 'run', tool_name: 'nested', query: nil, arguments: arguments)

    assert_equal({ name: 'Ada', tags: ['friend'] }, run_result[:result])
  end

  private

  def meta_service
    Tools::MetaToolService.new
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

  def build_nested_service
    Tools.const_set(:NestedService, Class.new do
      extend T::Sig
      extend ToolMeta

      tool_name 'nested'
      tool_description 'Return nested payload details'
      tool_param :payload, description: 'Nested payload'

      sig do
        params(
          payload: T::Hash[Symbol, T.untyped]
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def call(payload:)
        {
          name: payload[:user][:name],
          tags: payload[:user][:tags].map { |tag| tag[:label] }
        }
      end
    end)
  end

  def remove_constants
    Tools.send(:remove_const, :SampleService) if Tools.const_defined?(:SampleService, false)
    Tools.send(:remove_const, :NestedService) if Tools.const_defined?(:NestedService, false)
  end
end

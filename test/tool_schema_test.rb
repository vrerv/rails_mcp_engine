# frozen_string_literal: true

require 'test_helper'

module Tools
end

class ToolSchemaTest < Minitest::Test
  def setup
    ToolMeta.clear_registry
    Tools.send(:remove_const, :EchoServiceTest) if Tools.const_defined?(:EchoServiceTest, false)
  end

  def test_builds_schema_with_metadata_and_types
    service_class = build_echo_service
    schema = ToolSchema::Builder.build(service_class)

    assert_equal 'echo', schema[:name]
    assert_equal 'Echo message back', schema[:description]
    assert_equal :call, schema[:entrypoint]
    assert_equal service_class, schema[:service_class]

    message_param = schema[:params].find { |p| p[:name] == :message }
    times_param = schema[:params].find { |p| p[:name] == :times }

    assert_equal true, message_param[:required]
    assert_equal 'Message to echo', message_param[:description]
    assert_equal false, times_param[:required]
    assert_equal 'Times to repeat', times_param[:description]
  end

  def test_factories_generate_tool_classes
    service_class = build_echo_service
    schema = ToolSchema::Builder.build(service_class)

    ruby_tool = ToolSchema::RubyLlmFactory.build(service_class, schema)
    mcp_tool = ToolSchema::FastMcpFactory.build(service_class, schema)

    assert_equal 'Echo message back', ruby_tool.description(nil)
    assert_equal 'Echo message back', mcp_tool.description(nil)

    instance_result = ruby_tool.new.execute(message: 'hi', times: 2)
    mcp_result = mcp_tool.new.call(message: 'hi', times: 2)

    assert_equal 'hi hi', instance_result
    assert_equal 'hi hi', mcp_result
  end

  def test_fast_mcp_builder_handles_nested_object_params
    params_ast = [
      {
        name: :config,
        required: true,
        type: :object,
        children: [
          { name: :token, required: true, type: :string },
          { name: :retries, required: false, type: :integer }
        ]
      }
    ]

    arguments_proc = ToolSchema::FastMcpBuilder.arguments_block(params_ast)

    assert_silent do
      Class.new(ApplicationTool) do
        arguments(&arguments_proc)
      end
    end
  end

  def test_ruby_llm_builder_handles_any_type
    params_ast = [
      {
        name: :payload,
        required: true,
        type: :any,
        description: 'Any payload'
      }
    ]

    params_proc = ToolSchema::RubyLlmBuilder.params_block(params_ast)

    tool_class = Class.new(RubyLLM::Tool) do
      params(&params_proc)
    end

    schema = tool_class.new.params_schema
    payload_prop = schema['properties']['payload']

    assert_equal 'object', payload_prop['type']
    assert_equal true, payload_prop['additionalProperties']
    assert_equal 'Any payload', payload_prop['description']
  end

  def test_sorbet_type_mapper_handles_boolean_union
    service_class = Class.new do
      extend T::Sig

      sig { params(flag: T.nilable(T::Boolean)).returns(String) }
      def call(flag: nil); end
    end

    method = service_class.instance_method(:call)
    schema = ToolSchema::SorbetTypeMapper.map_signature(method)
    param = schema[:params].find { |p| p[:name] == :flag }

    assert_equal :boolean, param[:type]
    assert_equal false, param[:required]
  end

  def test_fast_mcp_builder_handles_boolean
    params_ast = [
      {
        name: :flag,
        required: true,
        type: :boolean,
        description: 'A flag'
      }
    ]

    arguments_proc = ToolSchema::FastMcpBuilder.arguments_block(params_ast)

    # This should not raise Dry::Core::Container::KeyError
    assert_silent do
      Class.new(ApplicationTool) do
        arguments(&arguments_proc)
      end
    end
  end

  private

  def build_echo_service
    Tools.const_set(:EchoServiceTest, Class.new do
      extend T::Sig
      extend ToolMeta

      tool_name 'echo'
      tool_description 'Echo message back'
      tool_param :message, description: 'Message to echo'
      tool_param :times, description: 'Times to repeat', required: false

      sig do
        params(
          message: String,
          times: T.nilable(Integer)
        ).returns(String)
      end
      def call(message:, times: nil)
        Array.new(times || 1, message).join(' ')
      end
    end)
  end
end

require 'test_helper'

class GemIntegrationTest < ActiveSupport::TestCase
  test 'gems are loaded' do
    assert defined?(RubyLLM), 'RubyLLM should be defined'
    assert defined?(FastMcp), 'FastMcp should be defined'
  end

  test 'tool generation works' do
    # Define a temporary test service
    service_class = Class.new do
      extend T::Sig
      extend ToolMeta

      tool_name 'integration_test_tool'
      tool_description 'Testing integration'

      sig { params(input: String).returns(String) }
      def call(input:)
        "echo: #{input}"
      end
    end

    # Assign to a constant so it has a name (required for tool generation)
    Tools.const_set(:IntegrationTestService, service_class)

    # Trigger generation
    schema = ToolSchema::Builder.build(service_class)
    ToolSchema::RubyLlmFactory.build(service_class, schema)
    ToolSchema::FastMcpFactory.build(service_class, schema)

    # Verify RubyLLM Tool
    llm_tool = Tools::IntegrationTest
    assert llm_tool < RubyLLM::Tool, 'Generated tool should inherit from RubyLLM::Tool'

    # Verify FastMCP Tool
    mcp_tool = Mcp::IntegrationTest
    assert mcp_tool < ApplicationTool, 'Generated tool should inherit from ApplicationTool'
    assert mcp_tool < FastMcp::Tool, 'Generated tool should inherit from FastMcp::Tool'
  ensure
    Tools.send(:remove_const, :IntegrationTestService) if Tools.const_defined?(:IntegrationTestService)
    Tools.send(:remove_const, :IntegrationTest) if Tools.const_defined?(:IntegrationTest)
    Mcp.send(:remove_const, :IntegrationTest) if Mcp.const_defined?(:IntegrationTest)
  end
end

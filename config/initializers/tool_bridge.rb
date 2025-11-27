# typed: strict
# frozen_string_literal: true

require_relative '../../app/lib/tool_meta'
require_relative '../../app/lib/tool_schema/builder'
require_relative '../../app/lib/tool_schema/ruby_llm_factory'
require_relative '../../app/lib/tool_schema/fast_mcp_factory'
require_relative '../../app/services/tools/meta_tool_service'

Rails.application.config.to_prepare do
  ToolMeta.registry.each do |service_class|
    schema = ToolSchema::Builder.build(service_class)
    ToolSchema::RubyLlmFactory.build(service_class, schema)
    ToolSchema::FastMcpFactory.build(service_class, schema)
  end
end

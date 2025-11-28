# frozen_string_literal: true

require 'json'
require 'pathname'
require 'ruby_llm'
require 'application_tool'

engine_root = Pathname.new(__dir__).join('..', '..', '..').expand_path
$LOAD_PATH.unshift(engine_root.join('app/lib').to_s) unless $LOAD_PATH.include?(engine_root.join('app/lib').to_s)
$LOAD_PATH.unshift(engine_root.join('app/services').to_s) unless $LOAD_PATH.include?(engine_root.join('app/services').to_s)

require engine_root.join('config/initializers/tool_bridge')

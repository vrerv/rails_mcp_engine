# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../app/lib', __dir__)
$LOAD_PATH.unshift File.expand_path('../app/services', __dir__)
$LOAD_PATH.unshift File.expand_path('..', __dir__)

require 'minitest/autorun'
require 'tool_meta'
require 'tool_schema/builder'
require 'tool_schema/ruby_llm_factory'
require 'tool_schema/fast_mcp_factory'

module RubyLLM
  class Tool
    def self.description(text = nil)
      @description = text if text
      @description
    end

    def self.params(&block)
      instance_eval(&block) if block
    end

    def self.object(_name, &block)
      instance_eval(&block) if block
    end

    def self.array(_name, of: nil, &block)
      @last_array_type = of
      instance_eval(&block) if block
    end

    def self.string(*); end

    def self.integer(*); end

    def self.float(*); end

    def self.boolean(*); end

    def self.any(*); end
  end
end

class ApplicationTool
  def self.description(text = nil)
    @description = text if text
    @description
  end

  def self.arguments(&block)
    instance_eval(&block) if block
  end

  def self.required(_name)
    ParamWrapper.new
  end

  def self.optional(_name)
    ParamWrapper.new
  end

  class ParamWrapper
    def hash(&block)
      instance_eval(&block) if block
      self
    end

    def array(_type = nil, &block)
      instance_eval(&block) if block
      self
    end

    def value(_type)
      self
    end
  end
end

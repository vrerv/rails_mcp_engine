# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

# ToolMeta defines a DSL for annotating service classes that represent tools.
# The metadata collected here becomes the source of truth for non-type
# attributes such as names, descriptions, and examples.
module ToolMeta
  extend T::Sig

  ParamMetadata = T.type_alias do
    T::Hash[Symbol, T.untyped]
  end

  class MissingSignatureError < StandardError; end

  sig { params(base: T.class_of(Object)).void }
  def self.extended(base)
    registry << base unless registry.include?(base)
    base.instance_variable_set(:@tool_params, T.let([], T::Array[ParamMetadata]))
    base.instance_variable_set(:@tool_name, nil)
    base.instance_variable_set(:@tool_description, nil)
  end

  sig { returns(T::Array[T.class_of(Object)]) }
  def self.registry
    @registry ||= []
  end

  sig { void }
  def self.clear_registry
    @registry = []
  end

  sig { params(name: String).void }
  def tool_name(name)
    @tool_name = name
  end

  sig { params(description: String).void }
  def tool_description(description)
    @tool_description = description
  end

  sig do
    params(
      name: T.any(String, Symbol),
      description: T.nilable(String),
      required: T::Boolean,
      example: T.untyped,
      enum: T.nilable(T::Array[T.untyped])
    ).void
  end
  def tool_param(name, description: nil, required: true, example: nil, enum: nil)
    @tool_params << {
      name: name.to_sym,
      description: description,
      required: required,
      example: example,
      enum: enum
    }
  end

  sig { returns(String) }
  def tool_entrypoint
    'call'
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def tool_metadata
    {
      name: @tool_name || default_tool_name,
      description: @tool_description || '',
      params: @tool_params,
      entrypoint: tool_entrypoint
    }
  end

  private

  sig { returns(String) }
  def default_tool_name
    return '' unless respond_to?(:name) && name

    name.split('::').last
        .gsub(/Service$/, '')
        .gsub(/([a-z0-9])([A-Z])/, '\\1_\\2')
        .downcase
  end
end

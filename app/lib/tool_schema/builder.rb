# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../tool_meta'
require_relative 'sorbet_type_mapper'

module ToolSchema
  class Builder
    extend T::Sig

    SchemaAst = T.type_alias do
      T::Hash[Symbol, T.untyped]
    end

    sig { params(service_class: T.class_of(Object)).returns(SchemaAst) }
    def self.build(service_class)
      metadata = T.let(service_class.tool_metadata, T::Hash[Symbol, T.untyped])
      entrypoint = metadata[:entrypoint]&.to_sym || :call
      method = service_class.instance_method(entrypoint)
      type_info = SorbetTypeMapper.map_signature(method)

      params_ast = type_info[:params].map do |param_ast|
        merge_param(param_ast, metadata[:params])
      end

      {
        name: metadata[:name],
        description: metadata[:description],
        type: metadata[:type],
        params: params_ast,
        return_type: type_info[:return_type],
        entrypoint: entrypoint,
        service_class: service_class
      }
    end

    sig do
      params(
        param_ast: T::Hash[Symbol, T.untyped],
        metadata_params: T.nilable(T::Array[T::Hash[Symbol, T.untyped]])
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def self.merge_param(param_ast, metadata_params)
      meta = metadata_params&.find { |p| p[:name].to_sym == param_ast[:name].to_sym }
      description = meta ? meta[:description] : nil
      example = meta ? meta[:example] : nil
      enum = meta ? meta[:enum] : nil
      required_from_meta = meta.nil? ? true : (meta[:required].nil? ? true : meta[:required])
      required = param_ast[:required] && required_from_meta

      param_ast.merge(
        description: description,
        example: example,
        enum: enum,
        required: required,
        children: merge_children(param_ast[:children], metadata_params)
      )
    end

    sig do
      params(children: T.untyped, metadata_params: T.nilable(T::Array[T::Hash[Symbol, T.untyped]])).returns(T.untyped)
    end
    def self.merge_children(children, metadata_params)
      return [] unless children.is_a?(Array)

      children.map do |child|
        merge_param(child, metadata_params)
      end
    end
  end
end

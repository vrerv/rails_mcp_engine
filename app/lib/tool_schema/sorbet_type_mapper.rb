# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module ToolSchema
  module SorbetTypeMapper
    extend T::Sig

    TypeAst = T.type_alias do
      T::Hash[Symbol, T.untyped]
    end

    sig { params(method: UnboundMethod).returns(T::Hash[Symbol, T.untyped]) }
    def self.map_signature(method)
      signature = T::Private::Methods.signature_for_method(method)
      raise ToolMeta::MissingSignatureError, "Missing Sorbet signature for #{method.name}" if signature.nil?

      params_ast = signature.arg_types.map do |name, type|
        map_param(name, type)
      end

      {
        params: params_ast,
        return_type: map_type(signature.return_type)
      }
    end

    sig { params(name: T.any(String, Symbol), type: T.untyped).returns(TypeAst) }
    def self.map_param(name, type)
      details = map_type(type)
      details.merge(name: name.to_sym)
    end

    sig { params(type: T.untyped).returns(TypeAst) }
    def self.map_type(type)
      nilable, inner_type = unwrap_nilable(type)
      mapped = case inner_type
               when T::Types::FixedHash
                 map_fixed_hash(inner_type)
               when T::Types::TypedArray
                 map_array(inner_type)
               when T::Types::TypedHash
                 map_hash(inner_type)
               when T::Types::Simple
                 map_simple(inner_type)
               when T::Types::Union
                 map_union(inner_type)
               else
                 { type: :any }
               end

      mapped.merge(required: !nilable)
    end

    sig { params(type: T::Types::Union).returns(TypeAst) }
    def self.map_union(type)
      non_nil_types = type.types.reject { |t| t.is_a?(T::Types::Simple) && t.raw_type == NilClass }
      return { type: :any } if non_nil_types.length != 1

      map_type(non_nil_types.first).merge(required: true)
    end

    sig { params(type: T::Types::TypedArray).returns(TypeAst) }
    def self.map_array(type)
      {
        type: :array,
        item_type: map_type(type.type)
      }
    end

    sig { params(type: T::Types::TypedHash).returns(TypeAst) }
    def self.map_hash(type)
      {
        type: :object,
        children: [],
        key_type: map_type(type.keys),
        value_type: map_type(type.values)
      }
    end

    sig { params(type: T::Types::FixedHash).returns(TypeAst) }
    def self.map_fixed_hash(type)
      children = type.keys.map do |key, value|
        mapped = map_type(value.type)
        mapped.merge(name: key.to_sym, required: value.required?)
      end

      {
        type: :object,
        children: children
      }
    end

    sig { params(type: T::Types::Simple).returns(TypeAst) }
    def self.map_simple(type)
      raw = type.raw_type
      case raw.name
      when 'String'
        { type: :string }
      when 'Integer'
        { type: :integer }
      when 'Float'
        { type: :float }
      when 'TrueClass', 'FalseClass'
        { type: :boolean }
      else
        if raw == T::Boolean
          { type: :boolean }
        else
          { type: :any }
        end
      end
    end

    sig { params(type: T.untyped).returns([T::Boolean, T.untyped]) }
    def self.unwrap_nilable(type)
      return [false, type] unless type.is_a?(T::Types::Union)
      nilable = type.types.any? { |t| t.is_a?(T::Types::Simple) && t.raw_type == NilClass }
      non_nil = type.types.reject { |t| t.is_a?(T::Types::Simple) && t.raw_type == NilClass }
      target = non_nil.length == 1 ? non_nil.first : type
      [nilable, target]
    end
  end
end

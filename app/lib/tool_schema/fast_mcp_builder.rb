# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module ToolSchema
  module FastMcpBuilder
    extend T::Sig

    sig { params(params_ast: T::Array[T::Hash[Symbol, T.untyped]]).returns(Proc) }
    def self.arguments_block(params_ast)
      proc do
        params_ast.each do |param|
          FastMcpBuilder.build_param(self, param)
        end
      end
    end

    sig { params(ctx: BasicObject, param: T::Hash[Symbol, T.untyped]).void }
    def self.build_param(ctx, param)
      wrapper = param[:required] ? ctx.required(param[:name]) : ctx.optional(param[:name])

      case param[:type]
      when :object
        wrapper.hash do
          nested_ctx = wrapper.respond_to?(:required) ? wrapper : ctx
          (param[:children] || []).each do |child|
            FastMcpBuilder.build_param(nested_ctx, child)
          end
        end
      when :array
        item = param[:item_type]
        if item && scalar_type?(item[:type])
          wrapper.array(scalar_symbol(item[:type]))
        elsif item&.dig(:type) == :object
          wrapper.array(:hash) do
            nested_ctx = wrapper.respond_to?(:required) ? wrapper : ctx
            (item[:children] || []).each do |child|
              FastMcpBuilder.build_param(nested_ctx, child)
            end
          end
        else
          wrapper.array(:any)
        end
      else
        wrapper.value(scalar_symbol(param[:type]))
      end
    end

    sig { params(type: T.untyped).returns(T::Boolean) }
    def self.scalar_type?(type)
      [:string, :integer, :float, :boolean, :any].include?(type)
    end

    sig { params(type: T.untyped).returns(Symbol) }
    def self.scalar_symbol(type)
      case type
      when :string then :string
      when :integer then :integer
      when :float then :float
      when :boolean then :boolean
      else :any
      end
    end
  end
end

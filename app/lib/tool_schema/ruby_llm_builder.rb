# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module ToolSchema
  module RubyLlmBuilder
    extend T::Sig

    sig { params(params_ast: T::Array[T::Hash[Symbol, T.untyped]]).returns(Proc) }
    def self.params_block(params_ast)
      proc do
        params_ast.each do |param|
          RubyLlmBuilder.build_param(self, param)
        end
      end
    end

    sig { params(ctx: BasicObject, param: T::Hash[Symbol, T.untyped]).void }
    def self.build_param(ctx, param)
      name = param[:name]
      case param[:type]
      when :object
        ctx.object(name) do
          (param[:children] || []).each do |child|
            RubyLlmBuilder.build_param(self, child)
          end
        end
      when :array
        item = param[:item_type]
        if item && scalar_type?(item[:type])
          ctx.array(name, of: scalar_symbol(item[:type]))
        elsif item&.dig(:type) == :object
          ctx.array(name) do
            object :item do
              (item[:children] || []).each do |child|
                RubyLlmBuilder.build_param(self, child)
              end
            end
          end
        else
          ctx.array(name)
        end
      when :any
        ctx.object(name, description: param[:description]) do
          additional_properties true
        end
      else
        method = scalar_method(param[:type])
        ctx.public_send(method, name)
      end
    end

    sig { params(type: T.untyped).returns(T::Boolean) }
    def self.scalar_type?(type)
      %i[string integer float boolean].include?(type)
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

    sig { params(type: T.untyped).returns(Symbol) }
    def self.scalar_method(type)
      case type
      when :integer then :integer
      when :float then :float
      when :boolean then :boolean
      else :string
      end
    end
  end
end

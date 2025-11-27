# frozen_string_literal: true

module T
  Boolean = Module.new
  Untyped = Object

  module Private
    module Methods
      @pending = {}
      @signatures = {}

      class << self
        def register(owner, sig_builder)
          @pending[owner] = sig_builder
        end

        def attach(owner, name)
          builder = @pending.delete(owner)
          return unless builder

          @signatures[[owner, name]] = builder.to_signature
        end

        def signature_for_method(method)
          @signatures[[method.owner, method.name]]
        end
      end
    end
  end

  module Sig
    def self.extended(base)
      base.singleton_class.prepend(MethodHook)
    end

    module MethodHook
      def method_added(name)
        T::Private::Methods.attach(self, name)
        super if defined?(super)
      end
    end

    def sig(&block)
      builder = Types::SignatureBuilder.new
      builder.instance_eval(&block)
      T::Private::Methods.register(self, builder)
      nil
    end
  end

  module Types
    class SignatureBuilder
      attr_reader :arg_types, :return_type

      def params(**kwargs)
        @arg_types = kwargs
        self
      end

      def returns(type)
        @return_type = type
        self
      end

      def void
        returns(NilClass)
      end

      def to_signature
        Signature.new(arg_types || {}, return_type)
      end
    end

    class Signature
      attr_reader :arg_types, :return_type

      def initialize(arg_types, return_type)
        @arg_types = arg_types
        @return_type = return_type
      end
    end

    class Simple
      attr_reader :raw_type

      def initialize(raw_type)
        @raw_type = raw_type
      end
    end

    class TypedArray
      attr_reader :type

      def initialize(type)
        @type = type
      end
    end

    class TypedHash
      attr_reader :keys_type, :values_type

      def initialize(keys_type, values_type)
        @keys_type = keys_type
        @values_type = values_type
      end
    end

    class Union
      attr_reader :types

      def initialize(types)
        @types = types
      end
    end

    class FixedHash
      class Field
        attr_reader :type

        def initialize(type, required: true)
          @type = type
          @required = required
        end

        def required?
          @required
        end
      end

      attr_reader :keys

      def initialize(keys)
        @keys = keys
      end
    end
  end

  module Array
    def self.[](type)
      Types::TypedArray.new(T.normalize_type(type))
    end
  end

  module Hash
    def self.[](*args)
      if args.length == 1 && args.first.is_a?(::Hash)
        keys = args.first.transform_values do |value|
          Types::FixedHash::Field.new(T.normalize_type(value), required: true)
        end
        Types::FixedHash.new(keys)
      else
        key_type, value_type = args
        Types::TypedHash.new(T.normalize_type(key_type), T.normalize_type(value_type))
      end
    end
  end

  def self.nilable(type)
    Types::Union.new([Types::Simple.new(::NilClass), normalize_type(type)])
  end

  def self.any(*types)
    Types::Union.new(types.map { |t| normalize_type(t) })
  end

  def self.class_of(klass)
    Types::Simple.new(klass)
  end

  def self.type_alias(&block)
    block.call
  end

  def self.let(value, _type)
    value
  end

  def self.untyped
    Untyped
  end

  def self.normalize_type(type)
    return type if type.is_a?(Types::Simple) || type.is_a?(Types::TypedArray) || type.is_a?(Types::TypedHash) || type.is_a?(Types::Union) || type.is_a?(Types::FixedHash)
    return type if type.is_a?(Module)

    Types::Simple.new(type)
  end
end

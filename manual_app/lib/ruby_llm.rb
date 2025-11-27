# frozen_string_literal: true

# Minimal stub of RubyLLM so the generated tools can be executed manually
# without pulling in the full dependency tree.
module RubyLLM
  class Tool
    class << self
      def description(text = nil)
        @description = text if text
        @description
      end

      def params(&block)
        instance_eval(&block) if block_given?
      end

      def object(_name)
        yield if block_given?
      end

      def array(_name, of: nil)
        @last_array_type = of
        yield if block_given?
      end

      def string(*); end
      def integer(*); end
      def float(*); end
      def boolean(*); end
      def any(*); end
    end

    # Generated tools define #execute; #call simply forwards to match the
    # RubyLLM::Tool interface exposed by the factories.
    def call(**kwargs)
      execute(**kwargs)
    end
  end
end

# frozen_string_literal: true

# Minimal FastMCP-style base class used by the factories. The manual test page
# doesn't exercise these tools directly, but we register them so the
# initializer mirrors a real host application.
class ApplicationTool
  class << self
    def description(text = nil)
      @description = text if text
      @description
    end

    def arguments(&block)
      instance_eval(&block) if block_given?
    end

    def required(_name)
      ParamWrapper.new
    end

    def optional(_name)
      ParamWrapper.new
    end
  end

  class ParamWrapper
    def hash(&block)
      instance_eval(&block) if block_given?
      self
    end

    def array(_type = nil, &block)
      instance_eval(&block) if block_given?
      self
    end

    def value(_type)
      self
    end
  end
end

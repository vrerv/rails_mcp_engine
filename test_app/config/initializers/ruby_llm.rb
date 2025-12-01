# frozen_string_literal: true

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch('OPENAI_API_KEY', nil)
  config.gemini_api_key = ENV.fetch('GEMINI_API_KEY', ENV.fetch('GOOGLE_API_KEY', nil))
  config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY', nil)
end

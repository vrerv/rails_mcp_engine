# frozen_string_literal: true

require 'test_helper'

class ChatControllerTest < Minitest::Test
  def test_openai_chat_preserves_the_chat_completions_protocol
    options = capture_chat_options('gpt-4.1', :openai)
    assert_equal 'gpt-4.1', options[:model]
    assert_equal :openai, options[:provider]
    if Gem::Version.new(RubyLLM::VERSION) >= Gem::Version.new('2.0')
      assert_equal :chat_completions, options[:protocol]
    else
      refute options.key?(:protocol)
    end
  end

  def test_native_providers_keep_their_default_protocol
    options = capture_chat_options('gemini-2.5-pro', :gemini)
    assert_equal :gemini, options[:provider]
    refute options.key?(:protocol)
  end

  private

  def capture_chat_options(model, provider)
    original = RubyLLM.method(:chat)
    options = {}
    RubyLLM.define_singleton_method(:chat) { |**kwargs| options.merge!(kwargs) }
    RailsMcpEngine::ChatController.new.send(:build_chat, model, provider)
    options
  ensure
    RubyLLM.define_singleton_method(:chat, original)
  end
end

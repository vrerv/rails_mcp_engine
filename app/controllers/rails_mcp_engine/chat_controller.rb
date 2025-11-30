# frozen_string_literal: true

require 'json'

module RailsMcpEngine
  class ChatController < ApplicationController
    def show
      @tools = schemas
      @models = [
        'gpt-4o',
        'gpt-4o-mini',
        'gpt-4-turbo',
        'gpt-3.5-turbo'
      ]
    end

    def send_message
      user_message = params[:message].to_s
      model = params[:model].to_s
      conversation_history = JSON.parse(params[:conversation_history] || '[]', symbolize_names: true)

      if user_message.strip.empty?
        render json: { error: 'Message is required' }, status: :bad_request
        return
      end

      # Create RubyLLM chat instance with configuration
      chat = RubyLLM.chat(
        provider: :openai,
        model: model
      )

      # Register all available tools
      tool_classes = get_tool_classes
      chat = tool_classes.reduce(chat) { |c, tool_class| c.with_tool(tool_class) }

      # Prepare the message with conversation history context
      if conversation_history.empty?
        # First message: just send as-is
        full_message = user_message
      else
        # Include conversation history for context
        context_parts = ['Previous conversation:']
        conversation_history.each do |msg|
          role_label = msg[:role] == 'user' ? 'User' : 'Assistant'
          context_parts << "#{role_label}: #{msg[:content]}"
        end
        context_parts << "\nCurrent question:"
        context_parts << user_message
        full_message = context_parts.join("\n\n")
      end

      # Ask the question and capture response
      begin
        # Ruby LLM handles tool calling automatically
        response = chat.ask(full_message)
        assistant_content = response.content

        # Build conversation history manually since Ruby LLM manages it internally
        # Add user message
        conversation_history << { role: 'user', content: user_message }
        # Add assistant response
        conversation_history << { role: 'assistant', content: assistant_content }

        # Tool results are handled transparently by Ruby LLM
        # We don't have direct access to them, so return empty array
        tool_results = []

        render json: {
          conversation_history: conversation_history,
          tool_results: tool_results
        }
      rescue StandardError => e
        render json: { error: e.message }, status: :bad_request
      end
    end

    private

    def schemas
      ToolMeta.registry.map { |service_class| ToolSchema::Builder.build(service_class) }
    end

    def get_tool_classes
      # Get all RubyLLM tool classes that were generated
      schemas.map do |schema|
        tool_constant = ToolSchema::RubyLlmFactory.tool_class_name(schema[:service_class])
        # Accessing Tools from global namespace
        ::Tools.const_get(tool_constant)
      end
    end
  end
end

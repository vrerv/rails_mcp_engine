# frozen_string_literal: true

Rails.application.routes.draw do
  root 'manual#show'

  post '/register_tool', to: 'manual#register', as: :register_tool
  post '/run_tool', to: 'manual#run', as: :run_tool
  delete '/delete_tool/:tool_name', to: 'manual#delete_tool', as: :delete_tool

  get '/chat', to: 'chat#show', as: :chat
  post '/chat/send', to: 'chat#send_message', as: :chat_send
end

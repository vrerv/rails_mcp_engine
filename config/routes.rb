RailsMcpEngine::Engine.routes.draw do
  get 'playground', to: 'playground#show', as: :playground
  post 'playground/register', to: 'playground#register', as: :playground_register
  post 'playground/run', to: 'playground#run', as: :playground_run
  delete 'playground/delete/:tool_name', to: 'playground#delete_tool', as: :playground_delete_tool

  get 'chat', to: 'chat#show', as: :chat
  post 'chat/send', to: 'chat#send_message', as: :chat_send
end

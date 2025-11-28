# frozen_string_literal: true

Rails.application.routes.draw do
  root 'manual#show'

  post '/register_tool', to: 'manual#register', as: :register_tool
  post '/run_tool', to: 'manual#run', as: :run_tool
end

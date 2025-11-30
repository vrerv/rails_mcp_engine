# frozen_string_literal: true

Rails.application.routes.draw do
  mount RailsMcpEngine::Engine => '/rails_mcp_engine'
  root to: redirect('/rails_mcp_engine/playground')
end

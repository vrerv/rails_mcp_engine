# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)

# Maintain your gem's version:
require 'rails_mcp_engine/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name        = 'rails_mcp_engine'
  spec.version     = RailsMcpEngine::VERSION
  spec.authors     = ['Soonoh Jung']
  spec.email       = ['soonoh.jung@gmail.com']
  spec.homepage    = 'https://github.com/sh1nj1/rails_mcp_engine'
  spec.summary     = 'Rails engine for MCP tools'
  spec.description = 'Unified tool definition pipeline for Rails 8 applications using FastMCP and RubyLLM.'
  spec.license     = 'MIT'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.required_ruby_version = '>= 3.2.0'

  spec.files = Dir['{app,config,db,lib}/**/*', 'MIT-LICENSE', 'Rakefile', 'README.md']

  spec.add_dependency 'fast-mcp', '~> 1.6'
  spec.add_dependency 'rails', '>= 7.1', '< 8.2'
  spec.add_dependency 'ruby_llm', '>= 1.9', '< 3'
  spec.add_dependency 'sorbet-runtime', '>= 0.5'
end

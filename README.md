# Rails MCP Engine

Rails MCP Engine provides a unified tool-definition pipeline for Rails 8 applications. Service classes declare Sorbet-typed signatures and metadata once, and the engine auto-generates both RubyLLM and FastMCP tool classes at boot.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rails_mcp_engine'
```

And then execute:

```bash
bundle install
```

## How it works

- **Service classes** live under the `Tools::` namespace, extend `ToolMeta`, and expose a single Sorbet-signed entrypoint (defaults to `#call`).
- **ToolMeta DSL** captures names, descriptions, and parameter metadata, while Sorbet signatures provide the type source of truth.
- The **ToolSchema pipeline** merges Sorbet type information with metadata, producing a unified schema AST.
- **Factories** (`ToolSchema::RubyLlmFactory` and `ToolSchema::FastMcpFactory`) transform the AST into RubyLLM tools and FastMCP `ApplicationTool` subclasses, respectively.
- The **Engine** automatically iterates through registered service classes and generates both tool types during Rails initialization (`to_prepare`).

## Defining a tool service

Create a service that extends `ToolMeta` and uses Sorbet for the entrypoint signature. Only business logic belongs here; tool wrappers are generated.

```ruby
# app/services/tools/book_meeting_service.rb
class Tools::BookMeetingService
  extend T::Sig
  extend ToolMeta

  tool_name "book_meeting"
  tool_description "Books a meeting."
  tool_param :window, description: "Start/finish window"
  tool_param :participants, description: "Email recipients"

  sig do
    params(
      window: T::Hash[Symbol, String],
      participants: T::Array[String]
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def call(window:, participants:)
    # ... business logic ...
  end
end
```

On boot, the engine generates:
- `Tools::BookMeeting < RubyLLM::Tool` with a matching `params` block.
- `Mcp::BookMeetingTool < ApplicationTool` with a matching `arguments` block.

## Default meta tool

`Tools::MetaToolService` is included by default to explore and execute registered tools at runtime. It exposes a single `action` argument with supporting keywords:

- `list`: return full tool details (name, description, params, return type).
- `list_summary`: return only names and descriptions.
- `search`: provide `query` to fuzzy-match name/description.
- `get`: provide `tool_name` to fetch a full schema payload.
- `run`: provide `tool_name` and `arguments` to invoke a tool through its service class.

> **Note:** The `register` action is not available via the tool interface for security reasons. Developers can manually register tools using `Tools::MetaToolService.new.register_tool("ClassName")` in their code.

Example invocation from a console:

```ruby
Tools::MetaToolService.new.call(action: 'run', tool_name: 'book_meeting', arguments: { window: { start: '...', finish: '...' }, participants: ['a@example.com'] })
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

### Manual Playground

The repository includes a minimal Rails app under `test_app/` for quick manual validation.

```bash
cd test_app
bundle install
bundle exec rails server -p 4000
```

See [`test_app/README.md`](test_app/README.md) for more details.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

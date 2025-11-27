# Rails MCP Engine

Rails MCP Engine provides a unified tool-definition pipeline for Rails 8 applications. Service classes declare Sorbet-typed signatures and metadata once, and the engine auto-generates both RubyLLM and FastMCP tool classes at boot.

## How it works
- **Service classes** live under the `Tools::` namespace, extend `ToolMeta`, and expose a single Sorbet-signed entrypoint (defaults to `#call`).
- **ToolMeta DSL** captures names, descriptions, and parameter metadata, while Sorbet signatures provide the type source of truth.
- The **ToolSchema pipeline** merges Sorbet type information with metadata, producing a unified schema AST.
- **Factories** (`ToolSchema::RubyLlmFactory` and `ToolSchema::FastMcpFactory`) transform the AST into RubyLLM tools and FastMCP `ApplicationTool` subclasses, respectively.
- The **initializer** (`config/initializers/tool_bridge.rb`) iterates through registered service classes and generates both tool types automatically during `to_prepare`.

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

## Development
- **Dependencies:** see `Gemfile` for required libraries (`sorbet-runtime`, `minitest`, `rubocop` for formatting).
- **Sorbet:** Run `bundle exec srb tc` to validate signatures and ensure service classes are annotated.
- **Autoloading:** Code lives under `app/lib` so Zeitwerk loads DSL and schema components automatically.
- **Formatting:** Use `rubocop -A` to keep the codebase consistent.

## Testing the pipeline
1. Define or update a `Tools::*Service` with `ToolMeta` and a Sorbet signature.
2. Boot the Rails app (e.g., `bundle exec rails console`). During initialization, the bridge builds tool classes.
3. Inspect generated constants: `Tools.constants` and `Mcp.constants` should include your tool wrappers.
4. Run the test suite locally with `ruby -Itest test/tool_schema_test.rb`.
5. Invoke through RubyLLM or FastMCP as usual; both delegate to the original service entrypoint.

## Default meta tool
`Tools::MetaToolService` is included by default to explore and execute registered tools at runtime. It exposes a single `action` argument with supporting keywords:

- `register`: `class_name` required (e.g., `Tools::BookMeetingService`) to dynamically add a tool and build both wrappers.
- `list`: return full tool details (name, description, params, return type).
- `list_summary`: return only names and descriptions.
- `search`: provide `query` to fuzzy-match name/description.
- `get`: provide `tool_name` to fetch a full schema payload.
- `run`: provide `tool_name` and `arguments` to invoke a tool through its service class.

Example invocation from a console:

```ruby
Tools::MetaToolService.new.call(action: 'run', tool_name: 'book_meeting', arguments: { window: { start: '...', finish: '...' }, participants: ['a@example.com'] })
```

Responses are hashes with either a `:tools`, `:tool`, or `:result` key, plus an `:error` message when validation fails.

## Notes
- Missing Sorbet signatures raise a `ToolMeta::MissingSignatureError` to enforce the contract.
- Parameter metadata is optional but recommended; required flags default to `true`.
- Unsupported union or complex types gracefully fall back to `:any` to avoid blocking generation.

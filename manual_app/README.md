# Manual Rails playground

This minimal Rails app lets you manually register and run tool services against the engine without setting up a full host application. It loads the engine code from the repository via shared load paths and exposes a single page UI for experimenting with tool definitions.

## Prerequisites
- Ruby 3.4.4
- Bundler (`gem install bundler`)

## Setup
Install dependencies from the `manual_app` directory:

```bash
cd manual_app
bundle install
```

## Running the playground
Start the Rails server (no database required):

```bash
bundle exec rails server -p 4000
```

Then open http://localhost:4000 to access the manual page.

## Using the manual page
1. **Register a tool**: Paste a Ruby class that extends `ToolMeta` and includes a Sorbet signature for its entrypoint. The app will `class_eval` the source and invoke `Tools::MetaToolService` to register both RubyLLM and FastMCP wrappers.
2. **Run a tool**: Select a registered tool and provide JSON arguments. The request is sent through the generated `RubyLLM::Tool` wrapper so you can inspect end-to-end execution.
3. **Inspect registered tools**: The page lists registered tool names, descriptions, and parameter names from the engine schema builder.

### Example tool source
```ruby
class Tools::EchoService
  extend T::Sig
  extend ToolMeta

  tool_description 'Echoes the provided payload'
  tool_param :message, description: 'Message to return'

  sig { params(message: String).returns(String) }
  def call(message:)
    message
  end
end
```

### Notes
- The playground evaluates arbitrary Ruby code; only run trusted tool source.
- All engine code is shared via `config.autoload_paths` in `config/application.rb`, so changes to the engine are immediately reflected when reloading the app.

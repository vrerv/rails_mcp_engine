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
1. **Register a tool**: Paste a Ruby class that extends `ToolMeta` and includes a Sorbet signature for its entrypoint. The app will `class_eval` the source and invoke `Tools::MetaToolService#register_tool` to register both RubyLLM and FastMCP wrappers.
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

## MCP Server Configuration

You can connect this app to MCP clients like **Claude Desktop**.

### 1. Claude Desktop Configuration

Add the following to your Claude Desktop configuration file:
- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "rails-mcp-engine": {
      "command": "bundle",
      "args": ["exec", "bin/mcp_stdio"],
      "cwd": "/absolute/path/to/rails_mcp_engine/manual_app",
      "env": {
        "RAILS_ENV": "development"
      }
    }
  }
}
```

Replace `/absolute/path/to/rails_mcp_engine/manual_app` with the actual absolute path on your machine.

### 2. Restart Claude Desktop

Restart Claude Desktop, and you should see the tools (e.g., `book_meeting`, `meta_tool`) available in the chat interface.

## Remote / SSE Configuration

To connect to this server as a "remote" server (e.g., via HTTP/SSE), you can use the SSE endpoint exposed by Rails.

1.  **Start the Rails Server**:
    ```bash
    bundle exec rails server -p 4000
    ```
    The SSE endpoint will be available at `http://localhost:4000/mcp/sse`.

2.  **Configure Claude Desktop**:
    Since Claude Desktop config requires a local command, use the `server-sse-client` bridge to connect to the remote URL.

    Add this to your `claude_desktop_config.json`:

    ```json
    {
      "mcpServers": {
        "rails-mcp-remote": {
          "command": "npx",
          "args": ["-y", "@modelcontextprotocol/server-sse-client", "--url", "http://localhost:4000/mcp/sse"],
          "env": {}
        }
      }
    }
    ```

    This tells Claude to run a local Node.js client that proxies requests to your Rails SSE endpoint.

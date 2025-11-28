require 'test_helper'
require 'net/http'
require 'uri'

class McpServerTest < ActionDispatch::SystemTestCase
  # Use rack_test driver since we are testing API endpoints, not browser UI
  # But user asked for "system test... runs the server".
  # driven_by :selenium, using: :headless_chrome would boot a real server.
  # driven_by :rack_test does NOT boot a real server on a port, it mocks requests.
  # To test "endpoint of the localhost", we need a real server.
  # Capybara with selenium/cuprite boots a server.

  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  test 'SSE endpoint streams data and lists tools' do
    # Capybara boots the app on a random port, accessible via `Capybara.current_session.server.port`
    port = Capybara.current_session.server.port
    host = Capybara.current_session.server.host
    base_url = "http://#{host}:#{port}"
    sse_url = URI("#{base_url}/mcp/sse")

    puts "Testing SSE endpoint at #{sse_url}"

    # Use curl to verify streaming
    curl_cmd = "curl -N -s -v #{sse_url}"
    puts "Running: #{curl_cmd}"

    # Run curl in a separate thread/process and read its output
    io = IO.popen(curl_cmd)

    endpoint_received = false
    tools_received = false

    reader_thread = Thread.new do
      while (line = io.gets)
        puts "Curl output: #{line.inspect}"
        endpoint_received = true if line.include?('event: endpoint')
        next unless line.include?('tools/list') || line.include?('MetaTool')

        tools_received = true
        Process.kill('TERM', io.pid)
        break
      end
    end

    sleep 2

    # Send tools/list request
    messages_url = URI("#{base_url}/mcp/messages")
    post_req = Net::HTTP::Post.new(messages_url)
    post_req.body = {
      jsonrpc: '2.0',
      method: 'tools/list',
      id: 1
    }.to_json
    post_req['Content-Type'] = 'application/json'

    puts "Sending tools/list request to #{messages_url}"
    Net::HTTP.start(messages_url.host, messages_url.port) do |msg_http|
      resp = msg_http.request(post_req)
      puts "POST response: #{resp.code} #{resp.body}"
      assert_equal '200', resp.code
    end

    reader_thread.join(10)
    begin
      io.close
    rescue StandardError
      nil
    end

    assert endpoint_received, 'Should have received endpoint event'
    assert tools_received, 'Should have received tools list'
  end
end

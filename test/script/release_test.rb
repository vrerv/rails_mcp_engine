# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative '../../script/release'

class ReleaseScriptTest < Minitest::Test
  class FakeRelease < Release
    attr_reader :commands
    attr_accessor :failure

    def initialize
      super
      @commands = []
    end

    def system(*args)
      @commands << args
      args != failure
    end
  end

  def setup
    @dir = Dir.mktmpdir('release test ')
    @release = FakeRelease.new
    @release.instance_variable_set(:@project_root, @dir)
    @release.instance_variable_set(:@build_dir, File.join(@dir, 'build/gems'))
    @release.instance_variable_set(:@changed_engines, ['rails_mcp_engine'])
    @release.instance_variable_set(:@engine_commits, { 'rails_mcp_engine' => ['abc change'] })
    @release.instance_variable_set(:@engine_versions, { 'rails_mcp_engine' => '0.4.4' })
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_version_edit_preserves_format_and_rollback_restores_files
    file = File.join(@dir, 'version.rb')
    original = "# frozen_string_literal: true\nmodule RailsMcpEngine\n  VERSION = '0.4.3'\nend\n"
    File.write(file, original)
    @release.send(:update_version_file, 'rails_mcp_engine', file, '0.4.4')
    assert_includes File.read(file), 'VERSION = "0.4.4"'
    assert_includes File.read(file), '# frozen_string_literal: true'
    @release.send(:update_release_notes, 'rails_mcp_engine', @dir, '0.4.4', ['abc change'])
    @release.send(:restore_originals)
    assert_equal original, File.read(file)
    refute File.exist?(File.join(@dir, 'RELEASE_NOTES.md'))
  end

  def test_test_failure_stops_before_publication
    @release.failure = ['bundle', 'exec', 'bin/rails', 'test']
    capture_io { assert_raises(SystemExit) { @release.send(:run_tests) } }
    refute @release.commands.any? { |command| command.first == 'gem' }
    refute @release.commands.include?(['bundle', 'exec', 'bin/rails', 'test:system'])
  end

  def test_build_failure_never_pushes
    @release.failure = ['gem', 'build', 'rails_mcp_engine.gemspec', '--output', File.join(@dir, 'build/gems/rails_mcp_engine-0.4.4.gem')]
    capture_io { assert_raises(SystemExit) { @release.send(:build_and_push_gems) } }
    refute @release.commands.any? { |command| command[0, 2] == ['gem', 'push'] }
  end

  def test_upload_uses_exact_artifact_and_explicit_host
    capture_io { @release.send(:build_and_push_gems) }
    assert_includes @release.commands, ['gem', 'push', File.join(@dir, 'build/gems/rails_mcp_engine-0.4.4.gem'), '--host', 'https://rubygems.org']
  end

  def test_commit_failure_stops_release
    @release.failure = ['git', 'add', 'lib/rails_mcp_engine/version.rb', 'RELEASE_NOTES.md', 'Gemfile.lock']
    capture_io { assert_raises(SystemExit) { @release.send(:commit_changes) } }
    refute @release.commands.any? { |command| command[0, 2] == ['git', 'commit'] }
  end

  def test_only_release_tag_is_pushed
    capture_io { @release.send(:finalize_release) }
    assert_includes @release.commands, ['git', 'push', 'origin', 'refs/tags/v0.4.4']
    refute @release.commands.flatten.include?('--tags')
  end
end

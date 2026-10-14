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

  def test_upload_failure_prints_the_same_host_and_quoted_path
    command = ['gem', 'push', File.join(@dir, 'build/gems/rails_mcp_engine-0.4.4.gem'), '--host', 'https://rubygems.org']
    @release.failure = command
    output, = capture_io { assert_raises(SystemExit) { @release.send(:build_and_push_gems) } }
    retry_line = output.lines.find { |line| line.start_with?('  gem push ') }
    assert_equal command, Shellwords.split(retry_line)
  end

  def test_remote_only_tag_is_rejected_and_missing_tag_is_allowed
    remote = File.join(@dir, 'remote.git')
    checkout = File.join(@dir, 'checkout')
    git!('init', '--bare', remote)
    git!('clone', '--no-tags', remote, checkout)
    Dir.chdir(checkout) do
      git!('-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '--allow-empty', '-m', 'initial')
      git!('tag', 'v0.4.4')
      git!('push', 'origin', 'HEAD', 'refs/tags/v0.4.4')
      git!('tag', '-d', 'v0.4.4')
      release = Release.new
      output, error = capture_io { assert_raises(SystemExit) { release.send(:check_remote_tag, '0.4.4') } }
      assert_includes output + error, 'Remote tag already exists'
      release.send(:check_remote_tag, '0.4.5')
      git!('remote', 'set-url', 'origin', File.join(@dir, 'missing.git'))
      output, error = capture_io { assert_raises(SystemExit) { release.send(:check_remote_tag, '0.4.5') } }
      assert_includes output + error, 'Could not verify remote tag'
    end
  end

  def with_release_history
    Dir.chdir(@dir) do
      git!('init')
      git!('config', 'user.name', 'Test')
      git!('config', 'user.email', 'test@example.com')
      version_file = File.join(@dir, 'version.rb')
      File.write(version_file, "VERSION = '0.4.2'\n")
      git!('add', '.')
      git!('commit', '-m', 'released 0.4.2')
      baseline = Open3.capture2('git', 'rev-parse', 'HEAD').first.strip
      File.write(File.join(@dir, 'feature.rb'), '# feature before version change\n')
      git!('add', '.')
      git!('commit', '-m', 'feature before version change')
      File.write(version_file, "VERSION = '0.4.3'\n")
      git!('commit', '-am', 'version change without release')
      File.write(File.join(@dir, 'feature.rb'), '# latest feature\n')
      git!('commit', '-am', 'latest feature')
      yield baseline, version_file
    end
  end

  def test_explicit_release_commit_includes_changes_before_version_edit
    with_release_history do |baseline, version_file|
      release = Release.new(['--last-release-commit', baseline[0, 8]])
      release.send(:validate_last_release_commit)
      commits = release.send(:changes_since_last_release, @dir, version_file)
      assert_equal 3, commits.size
      assert commits.any? { |c| c.include?('feature before version change') }
      assert commits.any? { |c| c.include?('version change without release') }
      refute commits.any? { |c| c.include?('released 0.4.2') }
      release.send(:update_release_notes, 'rails_mcp_engine', @dir, '0.4.4', commits)
      assert_includes File.read(File.join(@dir, 'RELEASE_NOTES.md')), 'feature before version change'
    end
  end

  def test_no_option_keeps_last_version_change_baseline
    with_release_history do |_, version_file|
      commits = Release.new.send(:changes_since_last_release, @dir, version_file)
      assert_equal 1, commits.size
      assert_includes commits.first, 'latest feature'
    end
  end

  def test_head_baseline_has_no_changes
    with_release_history do |_, version_file|
      sha = Open3.capture2('git', 'rev-parse', 'HEAD').first.strip
      release = Release.new(['--last-release-commit', sha])
      release.send(:validate_last_release_commit)
      assert_empty release.send(:changes_since_last_release, @dir, version_file)
    end
  end

  def test_invalid_or_unrelated_release_commit_is_rejected
    with_release_history do |_, _|
      ['HEAD', '--all', '0' * 40].each do |sha|
        release = Release.new(['--last-release-commit', sha])
        capture_io { assert_raises(SystemExit) { release.send(:validate_last_release_commit) } }
      end
      tree = Open3.capture2('git', 'rev-parse', 'HEAD^{tree}').first.strip
      capture_io do
        assert_raises(SystemExit) { Release.new(['--last-release-commit', tree]).send(:validate_last_release_commit) }
      end
      branch = Open3.capture2('git', 'branch', '--show-current').first.strip
      git!('checkout', '--orphan', 'unrelated')
      git!('commit', '-m', 'unrelated history')
      sha = Open3.capture2('git', 'rev-parse', 'HEAD').first.strip
      git!('checkout', branch)
      release = Release.new(['--last-release-commit', sha])
      output, error = capture_io { assert_raises(SystemExit) { release.send(:validate_last_release_commit) } }
      assert_includes output + error, 'must be an ancestor of HEAD'
    end
  end

  def test_option_errors_and_help
    [ ['--last-release-commit'], ['--unknown'], ['unexpected'] ].each do |args|
      capture_io { assert_raises(SystemExit) { Release.new(args) } }
    end
    output, = capture_io do
      exit_status = assert_raises(SystemExit) { Release.new(['--help']) }
      assert_equal 0, exit_status.status
    end
    assert_includes output, '--last-release-commit SHA'
  end

  def git!(*args)
    output, status = Open3.capture2e('git', *args)
    assert status.success?, output
  end

  def test_only_release_tag_is_pushed
    capture_io { @release.send(:finalize_release) }
    assert_includes @release.commands, ['git', 'push', 'origin', 'refs/tags/v0.4.4']
    refute @release.commands.flatten.include?('--tags')
  end
end

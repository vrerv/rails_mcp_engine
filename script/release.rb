#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "date"
require "rubygems"
require "open3"

# Adapted from sh1nj1/plan42 (Collavre), script/release.rb.

class Release
  COLORS = {
    red: "\e[0;31m",
    green: "\e[0;32m",
    yellow: "\e[1;33m",
    blue: "\e[0;34m",
    cyan: "\e[0;36m",
    reset: "\e[0m"
  }.freeze

  def initialize
    @project_root = File.expand_path("..", __dir__)
    @engines_dir = @project_root
    @build_dir = File.join(@project_root, "build", "gems")
    @release_branch = "release/#{Time.now.strftime('%Y%m%d-%H%M%S')}"
    @engines = ["rails_mcp_engine"]
    @engine_versions = {}
    @engine_commits = {}
    @changed_engines = []
    @original_contents = {}
  end

  def run
    Dir.chdir(@project_root)

    print_header
    check_prerequisites

    # Step 1: Analyze changes first (before creating branch)
    collect_changes_and_prompt_versions

    # Exit early if no changes
    if @changed_engines.empty?
      puts
      warn "✨ No engines have changes to release. Nothing to do!"
      exit 0
    end

    # Step 2: Create release branch and update files
    create_release_branch
    update_files_and_gemfile_lock

    # Step 3: Run tests (after version updates)
    run_tests

    # Step 4-6: Commit, build, push, finalize
    commit_changes
    build_and_push_gems
    finalize_release
  end

  private

  def git_output(*args)
    output, status = Open3.capture2("git", *args)
    abort "git #{args.first} failed" unless status.success?
    output
  end

  def print_header
    puts colorize(:blue, "========================================")
    puts colorize(:blue, "  Rails MCP Engine Release Script")
    puts colorize(:blue, "========================================")
  end

  def check_prerequisites
    current_branch = git_output("branch", "--show-current").strip
    unless current_branch == "main"
      error "Must be on main branch (currently on: #{current_branch})"
      exit 1
    end

    unless git_output("status", "--porcelain").strip.empty?
      error "Uncommitted changes exist. Please commit or stash first."
      exit 1
    end

    warn "Pulling latest from main..."
    system("git", "pull", "--ff-only", "origin", "main") || exit(1)
  end

  def collect_changes_and_prompt_versions
    puts
    success "[Step 1] Analyzing changes and collecting version input..."

    @engines.each do |engine|
      collect_engine_changes(engine)
    end
  end

  def collect_engine_changes(engine)
    engine_dir = @project_root
    version_file = File.join(engine_dir, "lib", engine, "version.rb")

    unless File.exist?(version_file)
      warn "#{engine}: version.rb not found, skipping"
      return
    end

    current_version = extract_version(version_file)
    last_version_commit = git_output("log", "-1", "--format=%H", "--", version_file).strip

    commits = if last_version_commit.empty?
      git_output("log", "--oneline", "--", engine_dir).lines.first(20)
    else
      git_output("log", "--oneline", "#{last_version_commit}..HEAD", "--", engine_dir).lines
    end

    commits = commits.map(&:strip).reject(&:empty?)

    if commits.any?
      @engine_commits[engine] = commits
      default_version = bump_patch_version(current_version)

      puts
      puts colorize(:cyan, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
      puts colorize(:blue, "#{engine}") + " (current: #{current_version})"
      puts colorize(:cyan, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
      puts
      puts colorize(:yellow, "Changes since last release:")
      commits.each { |c| puts "  • #{c}" }
      puts

      print "New version [#{colorize(:green, default_version)}]: "
      input = $stdin.gets
      abort "Release cancelled: no version input." unless input
      input = input.strip
      new_version = input.empty? ? default_version : input

      unless new_version.match?(/\A\d+\.\d+\.\d+\z/) && Gem::Version.new(new_version) > Gem::Version.new(current_version)
        abort "New version must be a higher MAJOR.MINOR.PATCH version."
      end
      abort "Tag already exists: v#{new_version}" if system("git", "show-ref", "--verify", "--quiet", "refs/tags/v#{new_version}")
      @engine_versions[engine] = new_version
      @changed_engines << engine

      puts colorize(:green, "→ #{engine} will be released as v#{new_version}")
    else
      puts colorize(:yellow, "#{engine}:") + " No changes since last release (staying at #{current_version})"
    end
  end

  def create_release_branch
    puts
    success "[Step 2] Creating release branch: #{@release_branch}"
    system("git", "checkout", "-b", @release_branch) || exit(1)
  end

  def update_files_and_gemfile_lock
    puts
    success "[Step 2] Updating version files and Gemfile.lock..."

    @changed_engines.each do |engine|
      engine_dir = @project_root
      version_file = File.join(engine_dir, "lib", engine, "version.rb")
      new_version = @engine_versions[engine]
      commits = @engine_commits[engine]

      update_version_file(engine, version_file, new_version)
      update_release_notes(engine, engine_dir, new_version, commits)
      info "  Updated #{engine} to v#{new_version}"
    end

    # Update Gemfile.lock
    warn "Updating Gemfile.lock..."
    remember_original(File.join(@project_root, "Gemfile.lock"))
    rollback_on_failure("bundle install failed") unless system("bundle", "install")
    success "Gemfile.lock updated"
  end

  # Snapshot a file before the release run overwrites it, so an aborted run can put
  # it back byte-for-byte. A nil snapshot means the file did not exist yet (e.g. the
  # first RELEASE_NOTES.md of a new engine) and must be deleted on rollback.
  def remember_original(path)
    @original_contents[path] = File.exist?(path) ? File.read(path) : nil unless @original_contents.key?(path)
  end

  def restore_originals
    @original_contents.each do |path, original|
      original.nil? ? FileUtils.rm_f(path) : File.write(path, original)
    end
  end

  def run_tests
    puts
    success "[Step 3] Running tests..."

    warn "Running release script tests..."
    rollback_on_failure("Release script tests failed") unless system("bundle", "exec", "ruby", "test/script/release_test.rb")
    warn "Running Rails tests..."
    rollback_on_failure("Rails tests failed") unless system("bundle", "exec", "bin/rails", "test")
    warn "Running Rails system tests..."
    rollback_on_failure("Rails system tests failed") unless system("bundle", "exec", "bin/rails", "test:system")

    success "All tests passed!"
  end

  def rollback_on_failure(reason)
    puts
    error reason
    # Undo the version bump before switching branches. A bare `git checkout main`
    # carries the uncommitted bump over to main, which both misreports the released
    # version and makes the next run abort on the "uncommitted changes" check.
    warn "Reverting version changes..."
    restore_originals
    warn "Rolling back to main branch..."
    # Keep the release branch for diagnosis; never delete work automatically.
    system("git", "checkout", "main")
    error "Release aborted. Please fix the issues and try again."
    exit 1
  end

  def extract_version(version_file)
    content = File.read(version_file)
    content.match(/VERSION\s*=\s*["']([^"']+)["']/)[1]
  end

  def bump_patch_version(version)
    parts = version.split(".")
    parts[2] = (parts[2].to_i + 1).to_s
    parts.join(".")
  end

  def update_version_file(engine, version_file, new_version)
    remember_original(version_file)
    content = File.read(version_file).sub(/(VERSION\s*=\s*)["'][^"']+["']/, "\\1#{new_version.inspect}")
    File.write(version_file, content)
  end

  def update_release_notes(engine, engine_dir, new_version, commits)
    release_notes_file = File.join(engine_dir, "RELEASE_NOTES.md")
    remember_original(release_notes_file)
    existing_content = File.exist?(release_notes_file) ? File.read(release_notes_file) : ""

    new_content = <<~MD
      ## v#{new_version} (#{Date.today})

      ### Changes
      #{commits.map { |c| "- #{c}" }.join("\n")}

    MD

    File.write(release_notes_file, new_content + existing_content)
  end

  def commit_changes
    puts
    success "[Step 4] Committing version updates..."

    changed_summary = @changed_engines.map { |e| "#{e}@#{@engine_versions[e]}" }.join(" ")
    system("git", "add", "lib/rails_mcp_engine/version.rb", "RELEASE_NOTES.md", "Gemfile.lock") || abort("git add failed")
    system("git", "commit", "-m", "chore(release): bump versions - #{changed_summary}") || abort("git commit failed")
    success "Committed version updates"
  end

  def build_and_push_gems
    puts
    success "[Step 5] Building and pushing gems..."

    FileUtils.mkdir_p(@build_dir)

    @changed_engines.each do |engine|
      engine_dir = @project_root
      new_version = @engine_versions[engine]
      gem_filename = "#{engine}-#{new_version}.gem"

      info "Building #{engine}..."
      Dir.chdir(engine_dir) do
        unless system("gem", "build", "#{engine}.gemspec", "--output", File.join(@build_dir, gem_filename))
          error "Failed to build #{engine}"
          exit 1
        end
      end

      gem_path = File.join(@build_dir, gem_filename)
      info "Pushing #{gem_filename}..."

      unless system("gem", "push", gem_path, "--host", "https://rubygems.org")
        error "Failed to push #{gem_filename}"
        puts
        warn "You can retry manually:"
        puts "  gem push #{gem_path}"
        exit 1
      end

      success "  ✓ #{gem_filename} pushed successfully"
    end

    success "All gems pushed!"
  end

  def finalize_release
    puts
    success "[Step 6] Finalizing release..."

    # Merge to main
    warn "Merging #{@release_branch} to main..."
    system("git", "checkout", "main") || exit(1)
    system("git", "merge", "--ff-only", @release_branch) || exit(1)

    # Push to origin
    warn "Pushing to origin..."
    system("git", "push", "origin", "main") || exit(1)

    # Create and push tags
    warn "Creating tags..."
    @changed_engines.each do |engine|
      tag = "v#{@engine_versions[engine]}"
      system("git", "tag", tag) || abort("Failed to create #{tag}")
      info "  Created tag: #{tag}"
    end
    system("git", "push", "origin", *@changed_engines.map { |engine| "refs/tags/v#{@engine_versions[engine]}" }) || exit(1)

    # Cleanup release branch
    system("git", "branch", "-d", @release_branch)

    print_final_summary
  end

  def print_final_summary
    puts
    puts colorize(:blue, "========================================")
    puts colorize(:green, "  🎉 Release complete!")
    puts colorize(:blue, "========================================")
    puts
    puts colorize(:yellow, "Released gems:")
    @changed_engines.each do |engine|
      puts "  • #{engine}-#{@engine_versions[engine]}"
    end
    puts
    puts colorize(:yellow, "Release notes:")
    @changed_engines.each do |engine|
      puts
      puts colorize(:cyan, "#{engine} v#{@engine_versions[engine]}:")
      @engine_commits[engine].each { |c| puts "  - #{c}" }
    end
  end

  def colorize(color, text)
    "#{COLORS[color]}#{text}#{COLORS[:reset]}"
  end

  def info(msg)
    puts colorize(:blue, msg)
  end

  def success(msg)
    puts colorize(:green, msg)
  end

  def warn(msg)
    puts colorize(:yellow, msg)
  end

  def error(msg)
    puts colorize(:red, "Error: #{msg}")
  end
end

Release.new.run if $PROGRAM_NAME == __FILE__

#!/usr/bin/env ruby

require "open3"
require "open-uri"
require "json"

Dir.chdir(__dir__)

FIRST_COMMIT = "7c1b30a602ab109d8d5388d7dfb3c5b180ba24e1" # r57410
BARE_REPO_DIR = File.join(__dir__, "ruby.git")
LOG_DIR = File.join(__dir__, "logs")
RUBY_REPO_URL = "https://github.com/ruby/ruby.git"
DOCKER_REPO_NAME = "rubylang/rubyfarm"
DOCKER_REPO_URL = "https://registry.hub.docker.com/v1/repositories/rubylang/rubyfarm/tags"

def fetch_all_commits
  unless File.exist?(BARE_REPO_DIR)
    system("git", "clone", "--bare", RUBY_REPO_URL, BARE_REPO_DIR)
  end
  list, = Open3.capture2("git", "--git-dir", BARE_REPO_DIR, "rev-list", FIRST_COMMIT + "..HEAD")
  list.lines.map {|commit| commit.chomp }
end

def fetch_built_commits
  json = open(DOCKER_REPO_URL) {|f| f.read }
  built = {}
  JSON.parse(json).each {|json| built[json["name"]] = true }
  built
end

def fetch_commits_to_build
  all = fetch_all_commits
  built = fetch_built_commits
  all.take_while {|commit| !built[commit] }.reverse
end

def build_and_push(commit)
  puts "build: #{ commit }"
  tag = "#{ DOCKER_REPO_NAME }:#{ commit }"
  Dir.mkdir(LOG_DIR) unless File.exist?(LOG_DIR)
  open(File.join(LOG_DIR, "#{ commit }.log"), "w") do |log|
    if system("docker", "build", "--no-cache", "--build-arg", "COMMIT=#{ commit }", "-t", tag, ".", out: log)
      system("docker", "tag", tag, "#{ DOCKER_REPO_NAME }:latest", out: log)
      system("docker", "push", tag, out: log)
      system("docker", "push", "#{ DOCKER_REPO_NAME }:latest", out: log)
      puts "pushed: #{ commit }"
    else
      puts "failed to build: #{ commit }"
    end
  end
end

fetch_commits_to_build.each do |commit|
  build_and_push(commit)
end

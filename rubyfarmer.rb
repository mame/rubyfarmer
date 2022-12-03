#!/usr/bin/env ruby

require "open3"
require "open-uri"
require "json"
require "net/https"

Dir.chdir(__dir__)

FIRST_COMMIT = "7c1b30a602ab109d8d5388d7dfb3c5b180ba24e1" # r57410
BARE_REPO_DIR = File.join(__dir__, "ruby.git")
LOG_DIR = File.join(__dir__, "logs")
RUBY_REPO_URL = "https://github.com/ruby/ruby.git"
DOCKER_REPO_NAME = "rubylang/rubyfarm"
DOCKER_REPO_URL = "https://registry.hub.docker.com/v2/repositories/rubylang/rubyfarm/tags"
LOCAL_DOCKER_REPO_NAME = ENV["RUBYFARM_LOCAL_DOCKER_REPO"] || "localhost:5000/rubyfarm"
SLACK_WEBHOOK_URL = ENV["SLACK_WEBHOOK_URL"]
PID_FILE = File.join(__dir__, "rubyfarmer.pid")

def log(msg)
  if SLACK_WEBHOOK_URL
    params = { text: msg }
    Net::HTTP.post(
      URI.parse(SLACK_WEBHOOK_URL),
      JSON.generate(params),
      "Content-Type" => "application/json"
    )
  else
    puts msg
  end
end

def fetch_built_commits
  built = {}
  url = DOCKER_REPO_URL + "?page_size=100"

  while url
    json = URI.open(url) {|f| f.read }
    json = JSON.parse(json)
    json["results"].each {|json| built[json["name"]] = true }
    url = json["next"]
  end

  built
end

def fetch_commits_to_build
  built = fetch_built_commits

  unless File.exist?(BARE_REPO_DIR)
    system("git", "clone", "--bare", RUBY_REPO_URL, BARE_REPO_DIR)
  end
  system("git", "--git-dir", BARE_REPO_DIR, "fetch", "-f", "origin", "master:master")

  # dag: commit -> [parent_commit]
  dag = {}
  list, = Open3.capture2("git", "--git-dir", BARE_REPO_DIR, "log", "--pretty=%H %P", FIRST_COMMIT + "..master")
  head = nil
  list.each_line do |line|
    commit, *parents = line.split
    dag[commit] = parents
    head ||= commit
  end

  # DFS and topological sort
  stack = [[:visit, head]]
  to_build = []
  visited = built.dup
  until stack.empty?
    type, commit = stack.pop
    if type == :visit
      next if visited[commit]
      visited[commit] = true
      stack << [:build, commit]
      dag[commit].each do |parent|
        stack << [:visit, parent]
      end
    else
      to_build << commit
    end
  end

  to_build
end

SIGCHLD_LOG = []
trap(:CHLD) { SIGCHLD_LOG << true }
def timeout_system(...)
  SIGCHLD_LOG.clear
  pid = Process.spawn(...)
  t = Time.now
  sleep 1 until SIGCHLD_LOG.size >= 1 || Time.now - t > 60 * 60
  Process.kill(:QUIT, pid)
  Process.waitpid(pid)
end

def build_and_push(commit)
  log "build: #{ commit }"
  tag = "#{ DOCKER_REPO_NAME }:#{ commit }"
  local_tag = "#{ LOCAL_DOCKER_REPO_NAME }:#{ commit }"
  Dir.mkdir(LOG_DIR) unless File.exist?(LOG_DIR)
  open(File.join(LOG_DIR, "#{ commit }.log"), "w") do |log|
    if timeout_system("docker", "build", "--force-rm", "--no-cache", "--build-arg", "COMMIT=#{ commit }", "-t", tag, ".", out: log)
      system("docker", "tag", tag, local_tag, out: log)
      system("docker", "rmi", "#{ DOCKER_REPO_NAME }:latest", out: log)
      system("docker", "tag", tag, "#{ DOCKER_REPO_NAME }:latest", out: log)
      system("docker", "rmi", "#{ LOCAL_DOCKER_REPO_NAME }:latest", out: log)
      system("docker", "tag", tag, "#{ LOCAL_DOCKER_REPO_NAME }:latest", out: log)
      system("docker", "push", tag, out: log)
      system("docker", "push", local_tag, out: log)
      system("docker", "push", "#{ DOCKER_REPO_NAME }:latest", out: log)
      system("docker", "push", "#{ LOCAL_DOCKER_REPO_NAME }:latest", out: log)
      system("docker", "rmi", tag, out: log)
      system("docker", "rmi", local_tag, out: log)
      system("docker", "image", "prune", "--filter", "label=stage=rubyfarmer-builder", "-f")
      log "pushed: #{ commit }"
    else
      log "failed to build: #{ commit }"
    end
  end
end

def main
  if File.exist?(PID_FILE)
    log "(still running)"
    return
  end

  begin
    File.write(PID_FILE, $$.to_s)
    gracefully = false

    commits = fetch_commits_to_build
    if !commits.empty?
      msg = "#{ commits.first }..#{ commits.last } (#{ commits.size } commits)"

      log "start: #{ msg }"

      commits.each do |commit|
        build_and_push(commit)
      end

      log "end: #{ msg }"
    end

    gracefully = true

  ensure
    log "abort: #{ $! }" if !gracefully

    File.delete(PID_FILE)
  end
end

main

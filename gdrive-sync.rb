#!/bin/ruby

require "rubygems"
require "bundler/setup"
require "rb-inotify"
require "observer"
require "yaml"

class Logger
  def log(msg)
    puts "#{Time.now.strftime "%H:%M:%S.%L"} #{msg}"
  end
end

class UserNotifier
  def initialize
    @app_name = "GDrive Sync"
  end

  def info(title, msg)
    `notify-send --urgency=normal --app-name="#{@app_name}" --category=Info --expire-time=1 "#{@app_name} - #{title}" "#{msg}"`
  end

  def warning(title, msg)
    `notify-send --urgency=critical --app-name="#{@app_name}" --category=Warning --icon=dialog-warning "#{@app_name} - #{title}" "#{msg}"`
  end
end

class FileSystemWatcher
  include Observable

  def initialize(logger, notifier, pathes)
    @logger = logger
    @notifier = notifier

    if pathes.is_a? String
      pathes = File.expand_path(pathes)
      dir,file = File.dirname(pathes),File.basename(pathes)
      @dirs_and_files = {dir => [file]}
    elsif pathes.is_a? Enumerable
      @dirs_and_files = pathes
        .map{|p| File.expand_path p}
        .map{|p| [File.dirname(p), File.basename(p)]}
        .reduce(Hash.new) do |h,i|
          dir,file = i[0],i[1]

          file_list = h[dir]
          if file_list.nil?
            file_list = [file]
            h[dir] = file_list
          else
            file_list.push file
          end

          h
        end
    else
      throw ArgumentError.new "Don't know what to do with 'pathes' as a '#{pathes.class.name}'"
    end
  end

  def start
    @dirs_and_files.each_key do |dir|
      file_list = @dirs_and_files[dir]
      @logger.log "[WATCHER] Starting to wath files in #{dir}:\n#{file_list.map{|f| "  - #{f}"}.join("\n")}"

      @notifier.watch(dir, :close_write, :moved_to) do |e|
        next unless file_list.include? e.name

        file = e.name
        path = File.join(dir, file)
        @logger.log "[WATCHER] #{e.flags.join(",")}: event detected for #{path}"
        changed
        notify_observers path, file, dir
      end
    end

    @running = true
    Thread.new do
      notifier_io = @notifier.to_io
      while @running
        if IO.select([notifier_io], [], [], 1)
          @notifier.process
        end
      end
    end
  end

  def stop
    @running = false
  end
end

class GDriveFileSynchronizer
  attr_reader :path, :state

  def initialize(logger, user_notifier, path)
    @logger = logger
    @user_notifier = user_notifier

    @path = path
    @state = :started
  end

  def handle_change
    cloud_ver = get_cloud_version
    local_ver = get_local_version

    case @state
    when :started
      if cloud_ver == local_ver
        versions_came_in_sync(cloud_ver)
      else
        versions_went_out_of_sync
      end
    when :unsynchronized
      if cloud_ver == local_ver
        versions_came_in_sync(cloud_ver)
      else
        still_out_of_sync
      end
    when :synchronized
      if cloud_ver == local_ver
        still_in_sync
      else
        if did_cloud_changed?(cloud_ver)
          versions_went_out_of_sync
        else
          push_local_to_cloud(local_ver)
        end
      end
    else
      throw "Unrecognized state '#{@state}'"
    end
  end

  def update(path, *args)
    handle_change if path == @path
  end

  private

  def still_in_sync
    @state = :synchronized
    @logger.log "[SYNC] No content change for #{@path}"
  end

  def still_out_of_sync
    @state = :unsynchronized
    @logger.log "[SYNC] Versions are still out of sync for #{@path}"
  end

  def versions_came_in_sync(cloud_ver)
    @last_known_cloud_ver = cloud_ver
    @state = :synchronized

    @logger.log "[SYNC] Local and Cloud versions are in sync (#{@path}, #{@last_known_cloud_ver})."
    @user_notifier.info "Auto-sync resumed", "Local and Cloud file versions are now in sync. Any local changes will be synced atuomatically for file '#{@path}'."
  end

  def versions_went_out_of_sync
    @state = :unsynchronized

    @logger.log "[SYNC] Cloud version changed since last sync. Resolve manually! File: #{@path}"
    @user_notifier.warning "Cloud version out of sync", "The file in the Cloud changed since the last sync. Resolve the issue manually. Once the Local and Cloud versions match automatic syncing will resume."
  end

  def push_local_to_cloud(cloud_ver)
    `yes | head -1 | drive push --force #{@path}`

    @last_known_cloud_ver = cloud_ver

    @logger.log "[SYNC] Local changes pushed to Cloud (#{@path}, #{@last_known_cloud_ver})."
    @user_notifier.info "File synced", "Local changes to file '#{@path}' are uploaded to Cloud."
  end

  def did_cloud_changed?(cloud_ver)
    cloud_ver != @last_known_cloud_ver
  end

  def get_cloud_version
    stat = `drive stat #{@path}`

    lines = stat.split("\n").map(&:strip)
    checksum = lines
      .select{|l| l.start_with? "Md5"}
      .first
      .split
      .last

    checksum
  end

  def get_local_version
    `md5sum #{@path}`.split(" ").first
  end
end

def default_config_file
  File.join File.dirname(__FILE__), "gdrive-sync.config.yaml"
end

def load_config(file)
  begin
    content = File.read file
    YAML.load content
  rescue
    return nil
  end
end

if $0 == __FILE__
  config_file = ARGV[0] || default_config_file
  config = load_config(config_file)
  if config.nil?
    puts [
      "No configuration file found at '#{config_file}'.",
      "Generating an empty one (try again after editing the above file)."
    ]

    File.write config_file, <<EOF
---
watch_files: []
EOF
    exit(-1)
  end

  files = config["watch_files"]
  if files.empty?
    puts "No files to watch. Exiting..."
    exit
  end

  logger = Logger.new
  user_notifier = UserNotifier.new
  logger.log "Starting GDrive-Sync service"
  logger.log "(Press Ctrl+C to exit)"

  watcher = FileSystemWatcher.new logger, INotify::Notifier.new, files

  files.each do |file|
    gdrive_sync = GDriveFileSynchronizer.new logger, user_notifier, file
    watcher.add_observer gdrive_sync
    gdrive_sync.handle_change
  end

  ["INT", "TERM"].each do |sig|
    Signal.trap(sig) do
      puts "Terminating..."
      watcher.stop
    end
  end

  watcher.start.join
end

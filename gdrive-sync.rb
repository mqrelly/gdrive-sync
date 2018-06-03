#!/bin/ruby

require "rubygems"
require "bundler/setup"
require "rb-inotify"
require "observer"

class Logger
  def log(msg)
    puts msg
  end
end

class UserNotifier
  def initialize
    @app_name = "GDrive Sync"
  end

  def info(title, msg)
    `notify-send --urgency=normal --app-name="#{@app_name}" --category=Info "#{title}" "#{msg}"`
  end

  def warning(title, msg)
    `notify-send --urgency=critical --app-name="#{@app_name}" --category=Warning "#{title}" "#{msg}"`
  end
end

class FileSystemWatcher
  include Observable

  def initialize(logger, notifier, pathes)
    @logger = logger
    @notifier = notifier

    if pathes.is_a? String
      dir,file = File.dirname(pathes),File.basename(pathes)
      @dirs_and_files = {dir => [file]}
    elsif pathes.is_a? Enumerable
      @dirs_and_files = pathes
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

    @notifier.run
  end
end

class LogObserver
  def initialize(logger)
    @logger = logger
  end

  def update(*args)
    @logger.log "[OBSERVER] Received: #{args.first}"
  end
end

class AggregatingObserver
  include Observable

  def initialize(logger, cooldown_in_millisec, checktime_in_millisec = 50)
    @logger = logger
    @cooldown_sec = cooldown_in_millisec / 1000
    @check_sec = checktime_in_millisec / 1000

    @thr = Thread.start do
      loop do
        sleep @check_sec
        trigger if cooldown_passed?
      end
    end
  end

  def update(*args)
    @logger.log "[AGGR] Received: #{args.first}"
    @last_event_time = Time.now
    @last_event_args = args
  end

  private

  def cooldown_passed?
    !@last_event_time.nil? && (@last_event_time + @cooldown_sec) < Time.now
  end

  def trigger
    @logger.log "[AGGR] trigger"
    changed
    notify_observers(*@last_event_args)
    @last_event_time = nil
  end
end

class GDriveFileSynchronizer
  attr_reader :path, :file, :dir, :state

  def initialize(path)
    @path = path
    @state = :unsynchronized
  end

  def handle_change
    if @state == :unsynchronized
      if are_local_and_cloud_in_sync?
        @last_known_cloud_ver = get_cloud_version
        @state = :synchronized
      end
    else
      if did_cloud_changed?
        @state = :unsynchronized
      else
        push_local_to_cloud
        @last_known_cloud_ver = get_cloud_version
      end
    end
  end

  private

  def push_local_to_cloud
    `yes | head -1 | drive push #{@path}`
  end

  def are_local_and_cloud_in_sync?
    diff = `drive diff #{@path}`
    diff.empty?
  end

  def did_cloud_changed?
    get_cloud_version == @last_known_cloud_ver
  end

  def get_cloud_version
    stat = `drive stat #{@path}`

    lines = stat.split("\n").map(&:strip)
    checksum = lines
      .select{|l| l.start_with? "Md5"}
      .first
      .split
      .last
    mod_time = lines
      .select{|l| l.start_with? "ModTime"}
      .first
      .split
      .last

    checksum + mod_time
  end
end


watcher = FileSystemWatcher.new Logger.new, INotify::Notifier.new, ARGV[0]
aggr = AggregatingObserver.new Logger.new, 3_000
watcher.add_observer aggr
obs = LogObserver.new Logger.new
aggr.add_observer obs
watcher.start

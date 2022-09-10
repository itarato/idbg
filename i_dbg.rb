# frozen_string_literal: true

###############################################################################
# DOCUMENTATION
###############################################################################

###############################################################################
# CONFIGURATION
###############################################################################

IDBG_LOGFILE = ENV["IDBG_LOGFILE"] || "/tmp/idbg.log"
IDBG_PROJECT_FOLDER = ENV["IDBG_PROJECT_FOLDER"] || "."
IDBG_SCRIPTS_FOLDER = ENV["IDBG_SCRIPTS_FOLDER"] || "/tmp"
IDBG_BACKTRACE_LEVEL_FILTERS = ENV["IDBG_BACKTRACE_LEVEL_FILTERS"]&.split(",") || []
IDBG_BACKTRACE_DEFAULT_LEVEL = 0
IDBG_SEMAPHORE_FILE = IDBG_SCRIPTS_FOLDER + "/once.txt"

###############################################################################
# CODE
###############################################################################

class IDbg
  # TODO: filter and exclusion patterns
  # TODO: inspector / breakpoint (~: yield if block evals to true)
  module AllMethodLogger
    @@with_args = false

    def self.with_args
      @@with_args = true
      self
    end

    def self.included(target)
      with_args = @@with_args
      @@with_args = false

      methods = target.instance_methods - target.class.superclass.instance_methods

      methods.each do |method|
        target.send(:alias_method, "__old_#{method}", method)

        target.define_method("__new_#{method}") do |*args|
          if with_args
            IDbg.log("Called: #{target}\##{method}", "Args", args)
          else
            IDbg.log("Called: #{target}\##{method}")
          end

          send("__old_#{method}", *args)
        end

        target.send(:alias_method, method, "__new_#{method}")
      end
    end
  end

  class << self
    def function_logger
      AllMethodLogger
    end

    def real_time_if(tag = :default)
      source = File.read(IDBG_SCRIPTS_FOLDER + "/break.rb")
      source += "\n#{tag.to_s}()"
      !!eval(source)
    rescue => e
      true
    end

    def break(tag = :default)
      source = File.read(IDBG_SCRIPTS_FOLDER + "/break.rb")
      source += "\n#{tag.to_s}()"
      binding.pry if eval(source)
    rescue => e
      binding.pry
    end

    def flash(*args)
      msg = args.map(&:to_s).join(' | ')
      system('osascript', '-e', 'display notification "' + msg + '" with title "IDbg - Ruby" subtitle "' + raw_signature + '"')
    end

    def log(*args)
      with_logfile { |f| f << "#{signature}\n\t\e[92m#{args.map(&:to_s).join(' | ')}\e[0m\n" }
      args[0]
    end

    def log_and_backtrace(*args, level: 2, line_limit: 1000)
      result = log(*args)

      backtrace(level, line_limit: line_limit)

      result
    end

    def backtrace(level = IDBG_BACKTRACE_DEFAULT_LEVEL, line_limit: 1000)
    	with_logfile do |f|
    		f << "#{signature} -- BACKTRACE\n\n"
        generate_backtrace(level, line_limit: line_limit) { |line| f << "\t" + line + "\n" }
	    	f << "\n"
    	end
    end

    def dump_backtrace(level = IDBG_BACKTRACE_DEFAULT_LEVEL, line_limit: 1000)
      generate_backtrace(level, line_limit: line_limit) { |line| puts line }

      nil
    end

    def count(key)
      if @counters == nil
        @counters = Hash.new(0)
      end

      @counters[key] += 1
      log("Count [#{key}] = #{@counters[key]}")
    end

    def run(script = 'scratchpad')
      eval(File.read(IDBG_SCRIPTS_FOLDER + "/#{script}.rb"))
    end

    def path?(path, method = 'GET')
      Rails.application.routes.recognize_path(path, method: method)
    end

    def once(tag)
      open(IDBG_SEMAPHORE_FILE, 'a+') {}

      f = File.open(IDBG_SEMAPHORE_FILE)
      flags = f.readlines.map(&:chomp)
      f.close

      if flags.include?(tag)
        log("Tag #{tag} has already run")
      end

      open(IDBG_SEMAPHORE_FILE, 'w+') { |f| f << "#{tag}\n" }

      log("Tag #{tag} is executed once now")
      yield
    end

    private

    def generate_backtrace(level = IDBG_BACKTRACE_DEFAULT_LEVEL, line_limit: 1000)
      backtrace = backtrace_list

      if level > 0
        backtrace.select! { |loc| Regexp.new(IDBG_BACKTRACE_LEVEL_FILTERS[level - 1]) =~ loc.to_s }
      end

      backtrace.take(line_limit).map { |loc| yield "\e[36m#{prettify_backtrace_location(loc)}\e[0m" }

      nil
    end

    def signature
    	"[\e[95m#{timestamp}\e[0m \e[2m#{caller}\e[0m]"
    end

    def raw_signature
      "#{timestamp} > #{backtrace_list[0]}"
    end

    def caller
    	prettify_backtrace_location(backtrace_list[0])
    end

    def backtrace_list
    	caller_locations.reverse.take_while { |loc| loc.to_s.index(__FILE__) == nil }.reverse
    end

    def prettify_backtrace_location(loc)
      loc
        .to_s
        .gsub(/:in `/, " \e[0m\e[33m")
        .gsub(/'/, "\e[0m")
    end

    def timestamp
    	Time.now.strftime('%T')
    end

    def with_logfile(&block)
      if !@has_log_file
        if Object.const_defined?("ActiveSupport::Notifications")
          ActiveSupport::Notifications.subscribe "process_action.action_controller" do |name, started, finished, unique_id, data|
            @has_log_file = false
            @counters = Hash.new(0)
          end
        end

        @has_log_file = true
        open(IDBG_LOGFILE, 'a+') do |f|
        	f << "\n\e[106m\e[1m\e[97m  --- LOG START @ #{Time.now} ---  \e[0m\n\n"
        	block.call(f)
        end
      else
        open(IDBG_LOGFILE, 'a+', &block)
      end
    end
  end
end

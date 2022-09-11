# frozen_string_literal: true

###############################################################################
# DOCUMENTATION
###############################################################################
#
# IDbg is an opinionated debug helper toolkit for the world where Ruby
# debugging is destroyed so much we need to back to `puts`.
#
# There are specific aspects this toolkit is trying to address:
# - debuggers are not reliable (JetBrain, debug-ide, pry, etc)
# - breaking is not always the best or desired way
# - updating code (even debugging code) can trigger a sluggish auto source-
#   -reload mechanism
# - debugging sometimes requires tricks

###############################################################################
# How to install?
#
# IDbg was designed for a Ruby backend workspace where things should stay
# separate (out of git) and low footprint. Hence my workflow is the following:
# - copy `i_dbg.rb` into one of the project folder that is autoloading this
#   file
# - add it to your global gitignore
# - edit the configurations (best is via environment variables, but if that
#   does not work, just hardcode it in the section below)
# - make a folder for aid scripts and temp files and set it in the config:
#   `IDBG_SCRIPTS_FOLDER`

###############################################################################
# How to use?
#
# Simplest example is to log messages uninterrupted. In a desired place insert
# a log:
#
# ```ruby
# # Some backend file you're debugging.
# ...
# class AppController < ApplicationController
#   def update
#     IDbg.log("Received params", params, @user, @ctx)
#   end
# end
# ```
#
# Then open the log and watch:
#
# ```bash
# $> tail -F /tmp/idbg.log
# ```

###############################################################################
# Components
#
# Component: logger
#
# Logger is logging all input to a semi-structured file, so it's both isolated
# and convenient for a watcher, without stopping code execution.
#
# ```ruby
# IDbg.log(@user, "was logged in with", @user_access)
# IDbg << "Or simply this."
# ```
#
# On Apple OS-X only the system notification can be used too:
#
# ```ruby
# IDbg.flash("User is deleted", @user)
# ```
#
# ---
# Component: instance call tracker
#
# Say you're interested in knowing the order of execution and what functions
# were executed in a class during a flow. IDbg allows logging all calls and
# with or without arguments:
#
# ```ruby
# class SomeClassgenerate_backtrace
#   # Insert before closing `end`:
#   include(IDbg.function_logger.with_args)
# end
# ```
#
# ---
# Component: complex debug script reactors
#
# Sometimes a debugging is just so convoluted or maybe it's even evolving into
# its own code that it's better to keep it somewhere else. As well - these
# scripts act as a signal.
# This has two flavors: execution of a custom script which breaks the flow
# with `pry` when it results truthy - and the other one that yields to a block
# when evals to truthy.
# Said scripts must be placed in `IDBG_SCRIPTS_FOLDER/break.rb` as functions.
#
# ```ruby
# # Inside IDBG_SCRIPTS_FOLDER/break.rb
# def my_script
#   # do some things
#   return true # in case we need a reaction
# end
#
# # Inside application code (will block with `binding.pry`, since its true):
# IDbg.break_if(:my_script)
#
# # Or a custom block version:
# IDbg.yield_if(:my_script) { Rails.cache.clear ; @user.reload }
# ```
# An expected side effect of these is that they do not trigger source-code
# reload when the script is updated.
#
# Call params can be passed/inspected too:
#
# ```ruby
# # Inside IDBG_SCRIPTS_FOLDER/break.rb
# def my_script
#   args = IDbg::DataBank.data
# end
#
# # Inside application code (will block with `binding.pry`, since its true):
# IDbg.break_if(:my_script, "arg1", { arg2: "foo" })
# ```
#
# It's also possible to run whole script files without expected reaction when
# the logic deserves its own file. These files are expected to exist in
# `IDBG_SCRIPTS_FOLDER/<NAME>.rb`:
#
# ```ruby
# IDbg.run("user_registration_script")
# ```
#
# ---
# Component: backtrace
#
# Often you want to know where you are in the execution. IDbg's backtrace
# can be customized with length and levels.
#
# ```ruby
# # Log a backtrace to the log file.
# IDbg.backtrace(level: 2)
# # Dump it right on the current output:
# IDbg.dump_backtrace
# # Combine backtrace and logging
# IDbg.backtrace(@user, @ctx)
# ```
#
# Levels are generally used by gradually filtering out external components,
# such as: gems > external libs > internal libs > components > ... Level 0
# is always the full backtrace.
# For configuration see: `IDBG_BACKTRACE_LEVEL_FILTERS`
# Example of a level setting where level-1 is filtering to all-except-gems and
# level-2 is only-rails-app:
# `export IDBG_BACKTRACE_LEVEL_FILTERS="my_project,my_project/app"`
#
# ---
# Component: counter
#
# Counter is counting each call.
#
# ```ruby
# IDbg.count("user-reload")
# ```
#
# ---
# Component: once-calls
#
# Sometimes a debugging or testing code snippet only should be called once
# only.
#
# ```ruby
# # Hypothetical loop where we only care about the first iteration.
# IDbg.reset_once(:cache_check)
# loop do
#   IDbg.once(:cache_check, @cache)
# end
# ```

###############################################################################
# CONFIGURATION
###############################################################################

#
# This log file is the main log collector.
# Recommended watch cmd: `tail -F <LOGFILE>`
#
IDBG_LOGFILE = ENV["IDBG_LOGFILE"] || "/tmp/idbg.log"

#
# Scripts folder is where auxiliary files are kept / created.
# It typically has:
# - break.rb (containing break script functions)
# - debug script files
# - once.txt (used for once-semaphores)
#
IDBG_SCRIPTS_FOLDER = ENV["IDBG_SCRIPTS_FOLDER"] || "/tmp"

#
# Backtrace levels are for narrowing down the scope of listed backtrace lines.
# For example gems, external libraries and non-app folders are not always
# useful in an investigation.
# This value expects a comma separated string list. Each string part is evaluated
# as a regular expression: when a backtrace is requested with level X, the
# backtrace only lists sources that matches with the (X - 1)th part.
#
IDBG_BACKTRACE_LEVEL_FILTERS = ENV["IDBG_BACKTRACE_LEVEL_FILTERS"]&.split(",") || []

#
# Default backtrace level. 0 is for a full backtrace list. (Typically the higher
# the level the less the backtrace is.)
#
IDBG_BACKTRACE_DEFAULT_LEVEL = 0

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

  class DataBank
    @@data = nil

    def self.with_data(*args)
      @@data = args
      result = yield
      @@data = nil

      result
    end

    def self.data = @@data
  end

  class << self
    def function_logger
      AllMethodLogger
    end

    def yield_if(fn = :default, *args)
      source = File.read(IDBG_SCRIPTS_FOLDER + "/break.rb")
      source += "\n#{fn.to_s}()"

      DataBank.with_data(args) { !!eval(source) }
    rescue => e
      true
    end

    def break_if(fn = :default, *args)
      source = File.read(IDBG_SCRIPTS_FOLDER + "/break.rb")
      source += "\n#{fn.to_s}()"

      DataBank.with_data(args) do
        if eval(source)
          binding.pry
        end
      end
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
    alias_method(:<<, :log)

    def backtrace(*args, level: IDBG_BACKTRACE_DEFAULT_LEVEL, line_limit: 1000)
      log(*args) if !args.empty?

    	with_logfile do |f|
    		f << "#{signature} -- BACKTRACE\n\n"
        generate_backtrace(level, line_limit: line_limit) { |line| f << "\t" + line + "\n" }
	    	f << "\n"
    	end

      args.first
    end

    def dump_backtrace(level: IDBG_BACKTRACE_DEFAULT_LEVEL, line_limit: 1000)
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

    def run(script, *args)
      DataBank.with_data(args) do
        eval(File.read(IDBG_SCRIPTS_FOLDER + "/#{script}.rb"))
      end
    end

    def path?(path, method = 'GET')
      Rails.application.routes.recognize_path(path, method: method)
    end

    def once(tag, *args)
      open(IDBG_SCRIPTS_FOLDER + "/once.txt", 'a+') {}

      f = File.open(IDBG_SCRIPTS_FOLDER + "/once.txt")
      flags = f.readlines.map(&:chomp)
      f.close

      if flags.include?(tag.to_s)
        log("Tag #{tag} has already run", *args)
        return
      end

      open(IDBG_SCRIPTS_FOLDER + "/once.txt", 'a+') { |f| f << "#{tag.to_s}\n" }

      log("Tag #{tag} is executed once now", *args)

      yield
    end

    def reset_once(*tags)
      f = File.open(IDBG_SCRIPTS_FOLDER + "/once.txt")
      flags = f.readlines.map(&:chomp)
      f.close

      flags -= tags.map(&:to_s)

      open(IDBG_SCRIPTS_FOLDER + "/once.txt", 'w+') { |f| f << flags.join("\n") }
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

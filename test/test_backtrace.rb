# frozen_string_literal: true

ENV["IDBG_BACKTRACE_LEVEL_FILTERS"] = "^((?!gem_wrap).)*$,^((?!_wrap).)*$"

require_relative("../i_dbg.rb")

def alpha
  IDbg.log('Without lib or gem wrap')
  IDbg.backtrace(level: 2)

  IDbg.log('Without gem wrap only')
  IDbg.backtrace(level: 1)

  IDbg.log('All')
  IDbg.backtrace("params", "another")

  IDbg.log('Source terminal log')
  IDbg.dump_backtrace
end

def beta
  lib_wrap { alpha }
end

def gamma
  lib_wrap { beta }
end

def delta
  lib_wrap { gamma }
end

def gem_wrap
  yield
end

def lib_wrap
  gem_wrap { yield }
end

delta

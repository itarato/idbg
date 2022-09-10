# frozen_string_literal: true

require_relative("../i_dbg.rb")

IDbg.log("Single message")
IDbg.log("Multiple messages", 123, [:start, :ship])

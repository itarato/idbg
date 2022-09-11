# frozen_string_literal: true

require("pry")

ENV["IDBG_SCRIPTS_FOLDER"] = "./tmp"

require_relative("../i_dbg.rb")

def alpha
  x = 1
  IDbg.break_if(:always_true, "hello", { foo: "bar" })
end

def beta
  x = 1
  IDbg.break_if(:always_false)
end

alpha
beta

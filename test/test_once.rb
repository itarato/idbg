# frozen_string_literal: true

require_relative("../i_dbg.rb")

IDbg.reset_once("foo", "bar")

a = 0

IDbg.once("foo", 1) { a += 1 }
IDbg.once("bar") { a += 10 }
IDbg.once("foo", 2) { a += 1 }
IDbg.once("bar") { a += 10 }
IDbg.once("foo", 3) { a += 1 }
IDbg.once("bar") { a += 10 }

IDbg.log("Should be 11", a)

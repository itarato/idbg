# frozen_string_literal: true

require_relative("../i_dbg.rb")

def alpha
  x = 1
  IDbg.break()
end

alpha

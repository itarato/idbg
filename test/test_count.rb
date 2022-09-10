# frozen_string_literal: true

require_relative("../i_dbg.rb")

5.times { IDbg.count(:first) }
3.times { IDbg.count(:second) }

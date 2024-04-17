# frozen_string_literal: true

require_relative("../i_dbg.rb")

IDbg.measure(:sample_block) do
    sleep(1.5)
end

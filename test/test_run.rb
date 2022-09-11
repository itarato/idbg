# frozen_string_literal: true

require("pry")

ENV["IDBG_SCRIPTS_FOLDER"] = "./tmp"

require_relative("../i_dbg.rb")

IDbg.run('my_script_1')

# frozen_string_literal: true

require_relative("../i_dbg.rb")

class Foo
  def initialize
    alpha(12)
  end

  def alpha(i)
    beta(foo: 123, key: :zibzub)
  end

  def beta(key:, **args)
    gamma(:a, :b, :c)
  end

  def gamma(*args)
  end

  include(IDbg.function_logger.with_args)
end

class Bar
  def initialize
    alpha(12)
  end

  def alpha(i)
    beta(foo: 123)
  end

  def beta(args)
    gamma(:a, :b, :c)
  end

  def gamma(*args)
  end

  include(IDbg.function_logger)
end

Foo.new
Bar.new

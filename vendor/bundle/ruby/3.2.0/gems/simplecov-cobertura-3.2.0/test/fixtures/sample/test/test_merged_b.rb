require_relative 'simplecov_setup'

class MergedBTest < Test::Unit::TestCase
  def test_greet_without_name
    assert_equal 'Hello, stranger!', Sample.new.greet(nil) # greet: then branch
  end
end

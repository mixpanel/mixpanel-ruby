require_relative 'simplecov_setup'

class MergedATest < Test::Unit::TestCase
  def test_greet_with_name
    assert_equal 'Hello, World!', Sample.new.greet('World') # greet: else branch
  end

  def test_absolute_positive
    assert_equal 5, Sample.new.absolute(5) # absolute: else branch
  end
end

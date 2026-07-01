require_relative 'simplecov_setup'

class SampleTest < Test::Unit::TestCase
  def test_greet_with_name
    assert_equal "Hello, World!", Sample.new.greet("World")
  end

  def test_absolute_positive
    # Only exercises the else branch (n >= 0), never the then branch (n < 0)
    assert_equal 5, Sample.new.absolute(5)
  end
end

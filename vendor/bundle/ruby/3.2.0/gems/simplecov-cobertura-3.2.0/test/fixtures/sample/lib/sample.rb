class Sample
  def greet(name)
    if name.nil?
      "Hello, stranger!"
    else
      "Hello, #{name}!"
    end
  end

  def absolute(n)
    if n < 0
      -n
    else
      n
    end
  end

  def unused_method
    x = 1
    y = 2
    z = x + y
    if z > 0
      "positive"
    else
      "non-positive"
    end
  end
end

# frozen_string_literal: true

class JsonLogic::Operations::Substr < JsonLogic::Operation
  def self.name = "substr"

  def call(values, _data)
    s, i, len = values
    str   = s.to_s
    start = i.to_i

    start += str.length if start < 0
    start = 0 if start < 0
    start = str.length if start > str.length

    return (str[start..-1] || "") if len.nil?

    l = len.to_i
    if l >= 0
      slice = str[start, l]
      slice.nil? ? "" : slice
    else
      end_excl = str.length + l
      end_excl = start if end_excl < start
      end_excl = str.length if end_excl > str.length
      length = end_excl - start
      length = 0 if length < 0
      str[start, length] || ""
    end
  end
end

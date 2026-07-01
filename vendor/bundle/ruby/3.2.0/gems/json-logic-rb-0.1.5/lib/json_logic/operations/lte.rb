# frozen_string_literal: true

using JsonLogic::Semantics

class JsonLogic::Operations::LTE < JsonLogic::Operation
  def self.name = "<="

  def call(values, _data)
    return values[0] <= values[1] if values.size == 2
    values.each_cons(2).all? { |a,b| a <= b }
  end
end

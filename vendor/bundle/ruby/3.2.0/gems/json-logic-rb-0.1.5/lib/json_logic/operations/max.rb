# frozen_string_literal: true

class JsonLogic::Operations::Max < JsonLogic::Operation
  def self.name = "max"

  def call(values, _data) = values.max
end

# frozen_string_literal: true

class JsonLogic::Operations::Cat < JsonLogic::Operation
  def self.name = "cat"

  def call(values, _data) = values.map!(&:to_s).join
end

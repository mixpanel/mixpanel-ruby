# frozen_string_literal: true

class JsonLogic::Operations::Merge < JsonLogic::Operation
  def self.name = "merge"
  def call(values, _data)
    values.flat_map { |v| v.is_a?(Array) ? v : [v] }
  end
end

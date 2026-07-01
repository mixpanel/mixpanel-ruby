# frozen_string_literal: true

class JsonLogic::Operations::StrictEqual < JsonLogic::Operation
  def self.name = "==="

  def call((a,b), _data)
    a === b
  end
end

# frozen_string_literal: true

class JsonLogic::Operations::Div < JsonLogic::Operation
  def self.name = "/"

  def call((a,b), _data) = (b.to_f == 0 ? nil : a.to_f / b.to_f)
end

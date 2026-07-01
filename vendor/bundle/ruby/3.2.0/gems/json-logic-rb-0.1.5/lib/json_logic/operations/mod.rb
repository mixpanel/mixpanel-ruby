# frozen_string_literal: true

class JsonLogic::Operations::Mod < JsonLogic::Operation
  def self.name = "%"

  def call((a,b), _data) = a.to_f % b.to_f
end

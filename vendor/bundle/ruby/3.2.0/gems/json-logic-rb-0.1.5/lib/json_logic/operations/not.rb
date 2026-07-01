# frozen_string_literal: true

using JsonLogic::Semantics

class JsonLogic::Operations::Not < JsonLogic::Operation
  def self.name = "!";

  def call((a), _data) = !a
end

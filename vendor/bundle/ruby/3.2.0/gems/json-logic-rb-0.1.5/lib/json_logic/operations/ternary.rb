# frozen_string_literal: true

using JsonLogic::Semantics

class JsonLogic::Operations::Ternary < JsonLogic::LazyOperation
  def self.name = "?:"

  def call((cond_rule, then_rule, else_rule), data)
    if !!JsonLogic.apply(cond_rule, data)
      JsonLogic.apply(then_rule, data)
    else
      JsonLogic.apply(else_rule, data)
    end
  end
end

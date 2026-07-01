# frozen_string_literal: true

using JsonLogic::Semantics
class JsonLogic::Operations::Or < JsonLogic::LazyOperation
  def self.name = "or"

  def call(args, data)
    args.each do |a|
      v = JsonLogic.apply(a, data)
      return v if !!v
    end

    args.empty? ? nil : JsonLogic.apply(args.last, data)
  end
end

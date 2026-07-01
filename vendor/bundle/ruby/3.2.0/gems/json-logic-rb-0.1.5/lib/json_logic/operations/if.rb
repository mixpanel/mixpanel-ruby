# frozen_string_literal: true

using JsonLogic::Semantics

class JsonLogic::Operations::If < JsonLogic::LazyOperation
  def self.name = "if"

  def call(args, data)
    i = 0
    while i < args.size - 1
      return JsonLogic.apply(args[i + 1], data) if !!(JsonLogic.apply(args[i], data))
      i += 2
    end
    return JsonLogic.apply(args[-1], data) if args.size.odd?
    nil
  end
end

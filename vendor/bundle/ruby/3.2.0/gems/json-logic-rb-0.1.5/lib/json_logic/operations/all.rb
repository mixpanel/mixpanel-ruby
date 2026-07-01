# frozen_string_literal: true

using JsonLogic::Semantics

class JsonLogic::Operations::All < JsonLogic::EnumerableOperation
  def self.name = "all"

  def call(args, data)
    items, rule_applied_to_each_item = resolve_items_and_per_item_rule(args, data)
    return false if items.empty?

    items.all? do |item|
      !!JsonLogic.apply(rule_applied_to_each_item, item)
    end
  end
end

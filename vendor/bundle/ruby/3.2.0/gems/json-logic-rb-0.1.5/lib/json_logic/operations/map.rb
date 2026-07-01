# frozen_string_literal: true

class JsonLogic::Operations::Map < JsonLogic::EnumerableOperation
  def self.name = "map"

  def call(args, data)
    items, rule_applied_to_each_item = resolve_items_and_per_item_rule(args, data)
    items.map { |item| JsonLogic.apply(rule_applied_to_each_item, item) }
  end
end

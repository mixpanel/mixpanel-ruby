class JsonLogic::EnumerableOperation < JsonLogic::LazyOperation
  private

  def resolve_items_and_per_item_rule(rules, data)
    rule_that_returns_items, rule_applied_to_each_item = rules
    items = Array(JsonLogic.apply(rule_that_returns_items, data))
    [items, rule_applied_to_each_item]
  end
end

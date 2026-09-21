# frozen_string_literal: true

module Mixpanel
  module Flags
    # A self-contained JsonLogic evaluator (https://jsonlogic.com).
    #
    # Flag definitions carry `runtime_evaluation_rule` trees authored in JsonLogic, so local
    # evaluation needs an interpreter for them. This used to come from the `json-logic-rb` gem,
    # which every host application had to resolve, and which exposed one process-wide operator
    # registry that we mutated to install `semver_compare` and `datetime_compare`. Both problems
    # go away by owning the walk: the registry below is private to this SDK, so registering an
    # operator here cannot change how a `json-logic-rb` rule elsewhere in the host application
    # evaluates.
    #
    # Semantics follow the JsonLogic reference implementation, which mirrors JavaScript rather
    # than Ruby: `==` coerces across types while `===` does not, comparisons coerce to numbers
    # unless both sides are strings, and 0, "", [] and nil are all falsy. Every operator here
    # is exercised against the official JsonLogic test suite in
    # spec/mixpanel-ruby/flags/json_logic_spec.rb.
    #
    # @api private
    module JsonLogic
      # Raised for a rule naming an operator we do not implement. Callers already treat a rule
      # they cannot evaluate as unsatisfied, and this stays an ArgumentError so a `json-logic-rb`
      # rescue keeps working.
      class UnknownOperatorError < ArgumentError; end

      # Operators registered via .add_operation, keyed by name. Mixpanel's own custom operators
      # live here; see custom_operators.rb.
      CUSTOM_OPERATIONS = {}

      # Operators that decide for themselves which arguments to evaluate, either to short-circuit
      # or because they rebind the data scope per item.
      LAZY_OPERATORS = %w[var and or if ?: map filter reduce all some none].freeze

      class << self
        # Evaluate a rule against a data scope.
        #
        # @param rule [Object] a JsonLogic rule tree, or any bare JSON value (returned as-is)
        # @param data [Hash, Array, nil] the scope `var` reads from
        # @raise [UnknownOperatorError] if the rule names an operator we do not implement
        def apply(rule, data = nil)
          evaluate(rule, data.nil? ? {} : data)
        end

        # Register an operator. The block receives the already-evaluated arguments and the current
        # data scope, and its return value becomes the operator's result.
        def add_operation(name, &block)
          CUSTOM_OPERATIONS[name.to_s] = block
        end

        private

        # --- evaluation ---------------------------------------------------------------

        def evaluate(rule, data)
          case rule
          when Array
            rule.map { |element| evaluate(element, data) }
          when Hash
            operator, arguments = rule.first
            dispatch(operator, arguments_for(arguments), data)
          else
            rule
          end
        end

        # A rule's argument list may be written as an array, or abbreviated to the bare single
        # argument -- `{"var" => "plan"}` means the same as `{"var" => ["plan"]}`.
        def arguments_for(arguments)
          case arguments
          when nil then []
          when Array then arguments
          else [arguments]
          end
        end

        def dispatch(operator, arguments, data)
          return apply_lazy(operator, arguments, data) if LAZY_OPERATORS.include?(operator)

          values = arguments.map { |argument| evaluate(argument, data) }
          custom = CUSTOM_OPERATIONS[operator]
          return custom.call(values, data) if custom

          apply_eager(operator, values, data)
        end

        def apply_lazy(operator, arguments, data)
          case operator
          when 'var' then op_var(arguments, data)
          when 'and' then op_and(arguments, data)
          when 'or' then op_or(arguments, data)
          when 'if', '?:' then op_if(arguments, data)
          when 'map' then each_item(arguments, data) { |items, rule| items.map { |item| evaluate(rule, item) } }
          when 'filter' then each_item(arguments, data) { |items, rule| items.select { |item| truthy?(evaluate(rule, item)) } }
          when 'all' then op_all(arguments, data)
          when 'some' then each_item(arguments, data) { |items, rule| items.any? { |item| truthy?(evaluate(rule, item)) } }
          when 'none' then each_item(arguments, data) { |items, rule| items.none? { |item| truthy?(evaluate(rule, item)) } }
          when 'reduce' then op_reduce(arguments, data)
          end
        end

        def apply_eager(operator, values, data)
          case operator
          when '==' then loose_equal?(values[0], values[1])
          when '!=' then !loose_equal?(values[0], values[1])
          when '===' then strict_equal?(values[0], values[1])
          when '!==' then !strict_equal?(values[0], values[1])
          when '!' then !truthy?(values[0])
          when '!!' then truthy?(values[0])
          when '>' then ordered?(values) { |order| order > 0 }
          when '>=' then ordered?(values) { |order| order >= 0 }
          when '<' then ordered?(values) { |order| order < 0 }
          when '<=' then ordered?(values) { |order| order <= 0 }
          when '+' then values.sum { |value| to_number(value) }
          when '-' then op_subtract(values)
          when '*' then values.inject(1.0) { |product, value| product * to_number(value) }
          when '/' then op_divide(values[0], values[1])
          when '%' then to_number(values[0]) % to_number(values[1])
          when 'max' then values.max { |a, b| compare(a, b) || 0 }
          when 'min' then values.min { |a, b| compare(a, b) || 0 }
          when 'in' then op_in(values[0], values[1])
          when 'cat' then values.map { |value| stringify(value) }.join
          when 'substr' then op_substr(values)
          when 'merge' then values.flat_map { |value| value.is_a?(Array) ? value : [value] }
          when 'missing' then missing_keys(missing_argument_keys(values), data)
          when 'missing_some' then op_missing_some(values[0], values[1], data)
          else raise UnknownOperatorError, "unknown JsonLogic operator: #{operator.inspect}"
          end
        end

        # --- operators ----------------------------------------------------------------

        # `var` resolves a dotted path, falling back to its second argument when the path is
        # absent. An empty or null path means "the whole scope", which is how `map` and friends
        # refer to the item they bound.
        def op_var(arguments, data)
          path_rule, default_rule = arguments
          path = evaluate(path_rule, data)
          return data if path.nil? || path == ''

          found, value = dig(data, path)
          return value if found

          default_rule.nil? ? nil : evaluate(default_rule, data)
        end

        # Returns the first falsy argument, or the last argument when every one is truthy, so that
        # `and` can be used to select a value and not only to test one.
        def op_and(arguments, data)
          result = nil
          arguments.each do |argument|
            result = evaluate(argument, data)
            return result unless truthy?(result)
          end
          result
        end

        # Mirror of #op_and: the first truthy argument, else the last one.
        def op_or(arguments, data)
          result = nil
          arguments.each do |argument|
            result = evaluate(argument, data)
            return result if truthy?(result)
          end
          result
        end

        # Arguments pair up as condition/value, so `if` covers both a ternary and a full
        # if/elsif/else chain. A trailing odd argument is the else branch.
        def op_if(arguments, data)
          index = 0
          while index < arguments.length - 1
            return evaluate(arguments[index + 1], data) if truthy?(evaluate(arguments[index], data))

            index += 2
          end
          arguments.length.odd? ? evaluate(arguments[-1], data) : nil
        end

        # `all` is false for an empty collection, whereas Ruby's Enumerable#all? is true.
        def op_all(arguments, data)
          each_item(arguments, data) do |items, rule|
            !items.empty? && items.all? { |item| truthy?(evaluate(rule, item)) }
          end
        end

        # Every collection operator takes a rule producing the items and a rule applied to each
        # one, with the item -- not the outer scope -- as the data the inner rule reads.
        def each_item(arguments, data)
          items_rule, item_rule = arguments
          items = Array(evaluate(items_rule, data))
          yield(items, item_rule)
        end

        # The step rule sees the item and the running total under the names the reference
        # implementation uses, on top of the outer scope.
        def op_reduce(arguments, data)
          items_rule, step_rule, initial_rule = arguments
          items = Array(evaluate(items_rule, data))

          items.inject(evaluate(initial_rule, data)) do |accumulator, item|
            scope = (data.is_a?(Hash) ? data : {}).merge(
              '' => item, 'current' => item, 'accumulator' => accumulator
            )
            evaluate(step_rule, scope)
          end
        end

        # A single argument negates; two subtract.
        def op_subtract(values)
          return 0.0 if values.empty?
          return -to_number(values[0]) if values.length == 1

          to_number(values[0]) - to_number(values[1])
        end

        # Division by zero has no JsonLogic answer, so it yields null rather than an infinity the
        # rest of the operators would have to special-case.
        def op_divide(numerator, denominator)
          divisor = to_number(denominator)
          return nil if divisor.zero?

          to_number(numerator) / divisor
        end

        # Substring for a string haystack, membership for an array one.
        def op_in(needle, haystack)
          case haystack
          when String then haystack.include?(stringify(needle))
          when Array then haystack.any? { |element| strict_equal?(element, needle) }
          else false
          end
        end

        # Negative offsets count back from the end, and a negative length trims that many
        # characters off the end instead of extending the slice.
        def op_substr(values)
          source, offset, length = values
          string = stringify(source)

          start = offset.to_i
          start += string.length if start.negative?
          start = start.clamp(0, string.length)

          return string[start..-1] || '' if length.nil?

          span = length.to_i
          span = (string.length + span - start) if span.negative?
          return '' if span <= 0

          string[start, span] || ''
        end

        # `missing` accepts its keys either spread across the argument list or wrapped in a single
        # array, so that it composes with operators that return one.
        def missing_argument_keys(values)
          values.length == 1 && values[0].is_a?(Array) ? values[0] : values
        end

        # A key counts as missing when it resolves to null or to the empty string, matching the
        # reference implementation -- a blank property is as good as an unset one for targeting.
        def missing_keys(keys, data)
          keys.select do |key|
            value = op_var([key], data)
            value.nil? || value == ''
          end
        end

        # Returns the missing keys only when too few of them are present to satisfy `minimum`.
        def op_missing_some(minimum, keys, data)
          list = keys.is_a?(Array) ? keys : Array(keys)
          missing = missing_keys(list, data)
          (list.length - missing.length) >= to_number(minimum) ? [] : missing
        end

        # --- value semantics ----------------------------------------------------------

        # Walks a dotted path. Returns [found, value] so that a stored nil or false is
        # distinguishable from an absent key -- `var`'s default only applies to the latter.
        def dig(data, path)
          current = data
          path.to_s.split('.').each do |key|
            case current
            when Array
              return [false, nil] unless key.match?(/\A\d+\z/)

              index = key.to_i
              return [false, nil] if index >= current.length

              current = current[index]
            when Hash
              if current.key?(key)
                current = current[key]
              elsif current.key?(key.to_sym)
                current = current[key.to_sym]
              else
                return [false, nil]
              end
            else
              return [false, nil]
            end
          end
          [true, current]
        end

        def truthy?(value)
          case value
          when nil, false then false
          when true then true
          when Float then !(value.zero? || value.nan?)
          when Numeric then !value.zero?
          when String, Array then !value.empty?
          else true
          end
        end

        # JavaScript's Number() coercion: booleans and null become 0 or 1, a blank string becomes
        # 0, a single-element array unwraps, and anything unparseable becomes NaN so that every
        # comparison against it is false.
        def to_number(value)
          case value
          when Numeric then value.to_f
          when true then 1.0
          when false, nil then 0.0
          when Array then to_number(to_primitive(value))
          when String then string_to_number(value)
          else Float::NAN
          end
        end

        def string_to_number(value)
          text = value.strip
          return 0.0 if text.empty?

          begin
            Float(text)
          rescue ArgumentError, TypeError
            Float::NAN
          end
        end

        def to_primitive(value)
          value.is_a?(Array) ? value.join(',') : value
        end

        def primitive?(value)
          value.is_a?(String) || value.is_a?(Numeric)
        end

        def boolean?(value)
          value == true || value == false
        end

        # JavaScript's `==`: equal types compare directly, and mixed ones are coerced -- booleans
        # and arrays to their primitive form, then strings and numbers numerically. null equals
        # only null.
        def loose_equal?(left, right)
          return left.nil? && right.nil? if left.nil? || right.nil?
          return numbers_equal?(left, right) if left.is_a?(Numeric) && right.is_a?(Numeric)
          return left == right if left.class == right.class
          return loose_equal?(to_number(left), right) if boolean?(left)
          return loose_equal?(left, to_number(right)) if boolean?(right)

          if primitive?(left) && primitive?(right)
            numbers_equal?(to_number(left), to_number(right))
          elsif (left.is_a?(Array) && primitive?(right)) || (right.is_a?(Array) && primitive?(left))
            loose_equal?(to_primitive(left), to_primitive(right))
          else
            false
          end
        end

        # JavaScript's `===`: no coercion, so only the single number type spans Integer and Float.
        def strict_equal?(left, right)
          return numbers_equal?(left, right) if left.is_a?(Numeric) && right.is_a?(Numeric)

          left.class == right.class && left == right
        end

        def numbers_equal?(left, right)
          a = to_number(left)
          b = to_number(right)
          return false if a.nan? || b.nan?

          a == b
        end

        # Two strings compare lexically; everything else compares as numbers. Returns nil when a
        # side is not a number, which makes every comparison against it fail.
        def compare(left, right)
          return left <=> right if left.is_a?(String) && right.is_a?(String)

          a = to_number(left)
          b = to_number(right)
          return nil if a.nan? || b.nan?

          a <=> b
        end

        # Three arguments express a between test -- `{"<" => [0, x, 10]}` -- by requiring the
        # ordering to hold across each adjacent pair.
        def ordered?(values)
          if values.length == 2
            order = compare(values[0], values[1])
            return nil if order.nil?

            return yield(order)
          end

          values.each_cons(2).all? do |left, right|
            order = compare(left, right)
            !order.nil? && yield(order)
          end
        end

        # Whole floats render without a trailing ".0", so arithmetic feeding `cat` reads the way
        # JsonLogic's number type would print.
        def stringify(value)
          return value if value.is_a?(String)
          return value.to_i.to_s if value.is_a?(Float) && value.finite? && value == value.to_i

          value.to_s
        end
      end
    end
  end
end

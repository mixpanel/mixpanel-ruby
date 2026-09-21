require 'json'
require 'spec_helper'
require 'mixpanel-ruby/flags/json_logic'

# The official JsonLogic test suite, vendored verbatim from https://jsonlogic.com/tests.json.
# Entries are either a section heading (a string) or a case of [rule, data, expected]. It is the
# contract for every operator, so the evaluator is measured against it rather than only against
# hand-written examples.
#
# Defined at the top level so the case table can be built while the describe blocks are collected.
JSONLOGIC_SUITE = File.expand_path('../../fixtures/jsonlogic_tests.json', __dir__)

def load_jsonlogic_suite
  section = ''
  JSON.parse(File.read(JSONLOGIC_SUITE)).each_with_index.filter_map do |entry, index|
    if entry.is_a?(String)
      section = entry
      next
    end

    rule, data, expected = entry
    ["#{index} #{section}: #{rule.to_json} against #{data.to_json}", rule, data, expected]
  end
end

JSONLOGIC_CASES = load_jsonlogic_suite

describe Mixpanel::Flags::JsonLogic do
  subject(:evaluator) { described_class }

  describe 'the official JsonLogic test suite' do
    it 'loads every case from the vendored suite' do
      expect(JSONLOGIC_CASES.length).to eq(278)
    end

    JSONLOGIC_CASES.each do |name, rule, data, expected|
      it name do
        result = evaluator.apply(rule, data)

        # The suite writes whole numbers as integers, while arithmetic here produces floats the
        # way JsonLogic's single number type does.
        if expected.is_a?(Numeric) && result.is_a?(Numeric)
          expect(result.to_f).to eq(expected.to_f)
        else
          expect(result).to eq(expected)
        end
      end
    end
  end

  describe 'unknown operators' do
    it 'raises so the caller can fail closed' do
      expect { evaluator.apply({ '=oops=' => [1, 1] }) }
        .to raise_error(described_class::UnknownOperatorError, /=oops=/)
    end

    it 'raises an ArgumentError, which is what json-logic-rb raised' do
      expect { evaluator.apply({ 'nope' => [] }) }.to raise_error(ArgumentError)
    end

    it 'raises for an operator nested inside a rule it would otherwise short-circuit past' do
      expect { evaluator.apply({ 'and' => [true, { 'nope' => [] }] }) }.to raise_error(ArgumentError)
    end
  end

  # The suite covers `var` against absent keys, but not against a key that is present and holding
  # a value JsonLogic considers falsy. A boolean custom property is an ordinary way to target a
  # flag, so these are called out separately.
  describe 'var against falsy values' do
    it 'reads a stored false rather than treating the key as absent' do
      expect(evaluator.apply({ 'var' => 'beta' }, { 'beta' => false })).to be(false)
    end

    it 'prefers a stored false over the default' do
      expect(evaluator.apply({ 'var' => %w[beta fallback] }, { 'beta' => false })).to be(false)
    end

    it 'prefers a stored nil over the default, because the key does exist' do
      expect(evaluator.apply({ 'var' => ['beta', 'fallback'] }, { 'beta' => nil })).to be_nil
    end

    it 'uses the default when the key is absent' do
      expect(evaluator.apply({ 'var' => %w[beta fallback] }, {})).to eq('fallback')
    end

    it 'reads a stored zero and empty string' do
      expect(evaluator.apply({ 'var' => 'count' }, { 'count' => 0 })).to eq(0)
      expect(evaluator.apply({ 'var' => 'name' }, { 'name' => '' })).to eq('')
    end

    it 'compares a stored false as false' do
      expect(evaluator.apply({ '==' => [{ 'var' => 'beta' }, false] }, { 'beta' => false })).to be(true)
      expect(evaluator.apply({ '!=' => [{ 'var' => 'beta' }, true] }, { 'beta' => false })).to be(true)
    end
  end

  # Context properties reach the evaluator as a Hash built by the caller, which may key it with
  # symbols rather than the strings a rule spells.
  describe 'symbol-keyed data' do
    it 'resolves a symbol key for a string path' do
      expect(evaluator.apply({ 'var' => 'plan' }, { plan: 'premium' })).to eq('premium')
    end

    it 'prefers a string key when both spellings are present' do
      expect(evaluator.apply({ 'var' => 'plan' }, { 'plan' => 'premium', plan: 'basic' })).to eq('premium')
    end

    it 'resolves a symbol key nested under a dotted path' do
      expect(evaluator.apply({ 'var' => 'account.plan' }, { account: { plan: 'premium' } })).to eq('premium')
    end
  end

  # The shapes the flags backend actually sends, spelled out so a change in the evaluator that
  # the suite tolerates still has to keep targeting rules working.
  describe 'targeting rules' do
    let(:context) { { 'plan' => 'premium', 'seats' => 25, 'country' => 'us', 'beta' => true } }

    it 'matches an equality rule' do
      expect(evaluator.apply({ '==' => [{ 'var' => 'plan' }, 'premium'] }, context)).to be(true)
      expect(evaluator.apply({ '==' => [{ 'var' => 'plan' }, 'basic'] }, context)).to be(false)
    end

    it 'matches a conjunction across properties' do
      rule = {
        'and' => [
          { '==' => [{ 'var' => 'plan' }, 'premium'] },
          { '>' => [{ 'var' => 'seats' }, 10] }
        ]
      }
      expect(evaluator.apply(rule, context)).to be(true)
      expect(evaluator.apply(rule, context.merge('seats' => 5))).to be(false)
    end

    it 'matches a disjunction' do
      rule = {
        'or' => [
          { '==' => [{ 'var' => 'country' }, 'ca'] },
          { '==' => [{ 'var' => 'country' }, 'us'] }
        ]
      }
      expect(evaluator.apply(rule, context)).to be(true)
      expect(evaluator.apply(rule, context.merge('country' => 'de'))).to be(false)
    end

    it 'matches membership in a list' do
      rule = { 'in' => [{ 'var' => 'country' }, %w[us ca gb]] }
      expect(evaluator.apply(rule, context)).to be(true)
      expect(evaluator.apply(rule, context.merge('country' => 'de'))).to be(false)
    end

    it 'matches a negation' do
      expect(evaluator.apply({ '!' => { 'var' => 'beta' } }, context)).to be(false)
      expect(evaluator.apply({ '!' => { 'var' => 'beta' } }, context.merge('beta' => false))).to be(true)
    end

    it 'matches a between test' do
      rule = { '<=' => [10, { 'var' => 'seats' }, 50] }
      expect(evaluator.apply(rule, context)).to be(true)
      expect(evaluator.apply(rule, context.merge('seats' => 75))).to be(false)
    end

    it 'fails a rule that reads a property the context does not carry' do
      expect(evaluator.apply({ '==' => [{ 'var' => 'tier' }, 'gold'] }, context)).to be(false)
      # An absent property reads as null, which coerces to 0 for a numeric comparison.
      expect(evaluator.apply({ '>' => [{ 'var' => 'tier' }, 1] }, context)).to be(false)
      expect(evaluator.apply({ '<' => [{ 'var' => 'tier' }, 1] }, context)).to be(true)
    end
  end

  # JsonLogic coerces the way JavaScript does, not the way Ruby does. These are the places the two
  # disagree, so they are the places a future change is most likely to get wrong.
  describe 'JavaScript coercion' do
    it 'compares across types for ==' do
      expect(evaluator.apply({ '==' => [1, '1'] })).to be(true)
      expect(evaluator.apply({ '==' => [1, 1.0] })).to be(true)
      expect(evaluator.apply({ '==' => [true, 1] })).to be(true)
      expect(evaluator.apply({ '==' => [false, 0] })).to be(true)
      expect(evaluator.apply({ '==' => [nil, false] })).to be(false)
      expect(evaluator.apply({ '==' => [nil, nil] })).to be(true)
    end

    it 'does not compare across types for ===, except between integers and floats' do
      expect(evaluator.apply({ '===' => [1, '1'] })).to be(false)
      expect(evaluator.apply({ '===' => [true, 1] })).to be(false)
      expect(evaluator.apply({ '===' => [1, 1.0] })).to be(true)
    end

    it 'treats 0, "" and [] as falsy' do
      expect(evaluator.apply({ '!!' => [0] })).to be(false)
      expect(evaluator.apply({ '!!' => [''] })).to be(false)
      expect(evaluator.apply({ '!!' => [[]] })).to be(false)
      expect(evaluator.apply({ '!!' => ['0'] })).to be(true)
      expect(evaluator.apply({ '!!' => [[0]] })).to be(true)
    end

    it 'compares two strings lexically and anything else numerically' do
      expect(evaluator.apply({ '<' => %w[a b] })).to be(true)
      expect(evaluator.apply({ '<' => ['10', '9'] })).to be(true)
      expect(evaluator.apply({ '<' => ['10', 9] })).to be(false)
    end

    it 'yields nil for a comparison against a value that is not a number' do
      expect(evaluator.apply({ '>' => ['apple', 1] })).to be_nil
      expect(evaluator.apply({ '<' => [nil, 'apple'] })).to be_nil
    end

    it 'yields NaN for arithmetic on a value that is not a number' do
      expect(evaluator.apply({ '+' => [1, 'apple'] })).to be_nan
    end

    it 'treats a blank string as zero' do
      expect(evaluator.apply({ '+' => [1, ' '] })).to eq(1)
    end

    it 'renders a whole number without a trailing zero' do
      expect(evaluator.apply({ 'cat' => ['total: ', { '+' => [1, 2] }] })).to eq('total: 3')
    end

    it 'yields nil rather than an infinity for division by zero' do
      expect(evaluator.apply({ '/' => [1, 0] })).to be_nil
    end
  end

  describe 'and / or as value selectors' do
    it 'returns the first falsy argument, else the last' do
      expect(evaluator.apply({ 'and' => [true, 'a'] })).to eq('a')
      expect(evaluator.apply({ 'and' => ['a', '', 'b'] })).to eq('')
    end

    it 'returns the first truthy argument, else the last' do
      expect(evaluator.apply({ 'or' => ['', 'b'] })).to eq('b')
      expect(evaluator.apply({ 'or' => ['', 0] })).to eq(0)
    end

    it 'does not evaluate past the argument that decides the result' do
      expect(evaluator.apply({ 'and' => [false, { 'nope' => [] }] })).to be(false)
      expect(evaluator.apply({ 'or' => [true, { 'nope' => [] }] })).to be(true)
    end
  end

  describe 'missing' do
    it 'counts a null or blank property as missing and a false one as present' do
      data = { 'a' => nil, 'b' => '', 'c' => false, 'd' => 1 }
      expect(evaluator.apply({ 'missing' => %w[a b c d e] }, data)).to eq(%w[a b e])
    end

    it 'accepts its keys wrapped in a single array' do
      expect(evaluator.apply({ 'missing' => [%w[a b]] }, { 'a' => 1 })).to eq(['b'])
    end
  end

  describe '.add_operation' do
    around do |example|
      registered = described_class::CUSTOM_OPERATIONS.dup
      example.run
      described_class::CUSTOM_OPERATIONS.replace(registered)
    end

    it 'registers an operator that receives evaluated arguments' do
      described_class.add_operation('shout') { |values, _data| values.map(&:upcase).join(' ') }

      expect(evaluator.apply({ 'shout' => [{ 'var' => 'plan' }, 'now'] }, { 'plan' => 'premium' }))
        .to eq('PREMIUM NOW')
    end

    # The gem this replaced registered into one process-wide engine, so installing an operator
    # here changed how an unrelated rule in the host application evaluated.
    it 'keeps the registry private to this SDK rather than process-wide' do
      expect(Mixpanel::Flags.const_defined?(:JsonLogic, false)).to be(true)
      expect(Object.const_defined?(:JsonLogic, false)).to be(false)
    end
  end
end

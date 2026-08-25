require 'json'
require 'rspec'
require 'json_logic'
require 'mixpanel-ruby/flags/custom_operators'

# The golden vectors are the cross-SDK contract for the custom operators; the canonical copy and its
# README live in the analytics monorepo. Cases run through JsonLogic.apply so that operator
# registration is covered alongside the comparison itself.
#
# Defined at the top level so the case tables can be built while the describe blocks are collected.
FIXTURES = File.expand_path('../../fixtures', __dir__)

# The property key the vectors are evaluated against. It is plumbing the spec supplies, so any name
# works as long as the rule and the data agree on it.
VECTOR_KEY = 'value'.freeze

def rule_for(operator, symbol, target)
  { "#{operator}_compare" => [{ 'var' => VECTOR_KEY }, symbol, target] }
end

# Build the event the rule reads from, omitting the key entirely for an unset property.
def data_for(subject)
  subject.nil? ? {} : { VECTOR_KEY => subject }
end

# Read a golden-vector file. String entries are headings, array entries are cases.
def load_vectors(operator)
  entries = JSON.parse(File.read(File.join(FIXTURES, "#{operator}_compare_tests.json")))

  section = ''
  cases = []
  entries.each_with_index do |entry, index|
    if entry.is_a?(String)
      section = entry
      next
    end
    subject, symbol, target, want = entry
    name = "#{index} #{section}: #{subject.to_json} #{symbol} #{target.to_json}"
    cases << [name, rule_for(operator, symbol, target), data_for(subject), want]
  end
  cases
end

SEMVER_CASES = load_vectors('semver')
DATETIME_CASES = load_vectors('datetime')

describe Mixpanel::Flags::CustomOperators do
  def apply(rule, data)
    JsonLogic.apply(rule, data)
  end

  describe 'semver_compare' do
    SEMVER_CASES.each do |name, rule, data, want|
      it name do
        expect(apply(rule, data)).to eq(want)
      end
    end
  end

  describe 'datetime_compare' do
    DATETIME_CASES.each do |name, rule, data, want|
      it name do
        expect(apply(rule, data)).to eq(want)
      end
    end
  end

  # An unset property must produce an event with no key at all, rather than a key holding a nil.
  # Both spellings fail closed, so the vectors alone cannot tell them apart.
  it 'omits the property for an unset subject' do
    expect(data_for(nil)).to eq({})
    expect(data_for('1.2.3')).to eq({ VECTOR_KEY => '1.2.3' })
  end
end

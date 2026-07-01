# frozen_string_literal: true

require_relative '../lib/json_logic'
require 'json'

path = ARGV[0] || File.expand_path('../spec/tmp/tests.json', __dir__)
abort("tests.json not found at #{path}") unless File.exist?(path)

payload = JSON.parse(File.read(path))

extract = lambda do |x|
  if x.is_a?(Array) && [2, 3].include?(x.size) && (x[0].is_a?(Hash) || x[0].is_a?(Array))
    rule, a2, a3 = x
    data, exp = (x.size == 2 ? [nil, a2] : [a2, a3])
    [rule, data, exp]
  elsif x.is_a?(Hash) && x.key?('rule')
    [x['rule'], x['data'], x['result'] || x['expected']]
  end
end

cases = []
stack = [payload]
while (n = stack.pop)
  if (c = extract.call(n))
    cases << c
  elsif n.is_a?(Array)
    n.size == 2 && n[0].is_a?(String) && n[1].is_a?(Array) ? stack << n[1] : n.each { |e| stack << e }
  elsif n.is_a?(Hash)
    n.each_value { |v| stack << v }
  end
end
abort("No tests found in #{path}") if cases.empty?

total = fail = 0
cases.each_with_index do |(rule, data, expected), i|
  total += 1
  begin
    got = JsonLogic.apply(rule, data)
    next if got == expected

    fail += 1
    puts "[FAIL ##{i + 1}] exp=#{expected.inspect} got=#{got.inspect} rule=#{rule.inspect} data=#{data.inspect}"
  rescue StandardError => e
    fail += 1
    puts "[ERROR ##{i + 1}] #{e.class}: #{e.message} rule=#{rule.inspect} data=#{data.inspect}"
  end
end

puts "Compliance: #{total - fail}/#{total} passed"
exit(fail.zero? ? 0 : 1)

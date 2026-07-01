# frozen_string_literal: true

class JsonLogic::Operations::MissingSome < JsonLogic::Operation
  def self.name = "missing_some"

  def call((min_ok, list), data)
    arr = list.is_a?(Array) ? list : Array(list)
    missing = arr.select { |k| dig(data, k).nil? }
    (arr.size - missing.size) >= min_ok ? [] : missing
  end

  private

  def dig(obj, path)
    return nil if obj.nil?
    cur = obj
    path.to_s.split(".").each do |k|
      if cur.is_a?(Array) && k =~ /\A\d+\z/
        cur = cur[k.to_i]
      elsif cur.is_a?(Hash)
        cur = cur[k] || cur[k.to_s] || cur[k.to_sym]
      else
        return nil
      end
    end
    cur
  end
end

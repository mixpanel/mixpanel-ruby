# frozen_string_literal: true

class JsonLogic::Operations::Var < JsonLogic::Operation
  def self.name = "var";
  def self.values_only? = false

  def call((path_rule, fallback_rule), data)
    path = JsonLogic.apply(path_rule, data)
    return data if path == ""
    val = dig(data, path)
    return val unless val.nil?
    return nil if fallback_rule.nil?
    JsonLogic.apply(fallback_rule, data)
  end

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

# frozen_string_literal: true

class JsonLogic::Operations::Missing < JsonLogic::Operation
  def self.name = "missing"

  def call(values, data)
    keys =
      if values.size == 1 && values.first.is_a?(Array)
        values.first
      else
        values
      end

    keys.select { |k| dig(data, k).nil? }
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

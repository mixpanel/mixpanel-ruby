# frozen_string_literal: true

module JsonLogic
  module Semantics
    module_function

    def truthy?(v)
      case v
      when nil
        false
      when TrueClass, FalseClass
        v
      when Numeric
        v.zero? ? false : true
      when String
        v.empty? ? false : true
      when Array
        v.empty? ? false : true
      else
        true
      end
    end

    def to_primitive(v)
      case v
      when Array then v.join(',')
      else v
      end
    end

    def num(v)
      case v
      when Numeric    then v.to_f
      when TrueClass  then 1.0
      when FalseClass then 0.0
      when NilClass   then 0.0
      when Array      then num(to_primitive(v))
      when String
        s = v.strip
        return 0.0 if s.empty?
        begin
          Float(s)
        rescue ArgumentError
          Float::NAN
        end
      else
        Float::NAN
      end
    end

    def eq(a, b)
      if a.class == b.class
        if a.is_a?(Numeric)
          ax = a.to_f; bx = b.to_f
          return false if ax.nan? || bx.nan?
          return ax == bx
        else
          return a.eql?(b)
        end
      end

      if a.nil? && b.nil?
        return true
      elsif a.nil? || b.nil?
        return false
      end

      if a.is_a?(TrueClass) || a.is_a?(FalseClass)
        return eq(num(a), b)
      end
      if b.is_a?(TrueClass) || b.is_a?(FalseClass)
        return eq(a, num(b))
      end

      if (a.is_a?(String) && b.is_a?(Numeric)) || (a.is_a?(Numeric) && b.is_a?(String))
        ax = num(a); bx = num(b)
        return false if ax.nan? || bx.nan?
        return ax == bx
      end

      if (a.is_a?(Array) && (b.is_a?(String) || b.is_a?(Numeric))) ||
         (b.is_a?(Array) && (a.is_a?(String) || a.is_a?(Numeric)))
        return eq(to_primitive(a), to_primitive(b))
      end

      false
    end

    def cmp(a, b)
      if a.is_a?(String) && b.is_a?(String)
        a <=> b
      else
        x = num(a); y = num(b)
        return nil if x.nan? || y.nan?
        x <=> y
      end
    end

    refine Object do
      def !@
        JsonLogic::Semantics.truthy?(self) ? false : true
      end

      def to_bool
        JsonLogic::Semantics.truthy?(self)
      end
    end

    [String, Integer, Float, NilClass, Array, TrueClass, FalseClass].each do |klass|
      refine klass do
        def ==(other) = JsonLogic::Semantics.eq(self, other)
        def >(other)  = (c = JsonLogic::Semantics.cmp(self, other)) && c == 1
        def >=(other) = (c = JsonLogic::Semantics.cmp(self, other)) && (c == 1 || c == 0)
        def <(other)  = (c = JsonLogic::Semantics.cmp(self, other)) && c == -1
        def <=(other) = (c = JsonLogic::Semantics.cmp(self, other)) && (c == -1 || c == 0)
      end
    end
  end
end

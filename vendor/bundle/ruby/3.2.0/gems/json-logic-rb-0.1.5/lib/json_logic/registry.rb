# lib/json_logic/registry.rb

module JsonLogic
  class Registry
    def initialize(map = {})
      @map = map.dup
    end

    def register(op_class)
      name = op_class.name or raise ArgumentError, 'name missing'
      @map[name.to_s] = op_class
      self
    end

    def fetch(name)
      @map[name.to_s]
    end
  end
end

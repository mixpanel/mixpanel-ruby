# frozen_string_literal: true

require_relative 'json_logic/version'
require_relative 'json_logic/semantics'
require_relative 'json_logic/operation'
require_relative 'json_logic/lazy_operation'
require_relative 'json_logic/enumerable_operation'
require_relative 'json_logic/registry'
require_relative 'json_logic/engine'

module JsonLogic
  module Operations
  end
end


# Load operation classes (each file defines one class with .name)
Dir[File.join(__dir__, 'json_logic', 'operations', '*.rb')].sort.each { |f| require f }

# Auto-register all operation classes with .name
module JsonLogic
  module Loader
    module_function

    def register_all!(registry)
      ObjectSpace.each_object(Class) do |klass|
        next unless klass < JsonLogic::Operation
        next unless klass.respond_to?(:name) && klass.name && !klass.name.to_s.empty?

        registry.register(klass)
      end
    end
  end

  class << self
    def apply(rule, data = nil)
      Engine.default.evaluate(rule, data)
    end

    def add_operation(name, lazy: false, &block)
      base = lazy ? JsonLogic::LazyOperation : JsonLogic::Operation
      klass = Class.new(base) do
        define_singleton_method(:name) { name.to_s }
        define_method(:call) { |args, data| block.call(args, data) }
      end
      JsonLogic::Engine.default.registry.register(klass)
      klass
    end
  end
end

JsonLogic::Loader.register_all!(JsonLogic::Engine.default.registry)

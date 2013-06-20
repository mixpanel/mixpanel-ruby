require File.join(File.dirname(__FILE__), 'mixpanel-ruby/people.rb')
require File.join(File.dirname(__FILE__), 'mixpanel-ruby/events.rb')

module Mixpanel
  class Tracker < Events
    attr_reader :people

    def initialize(token, consumer=nil, &block)
      super(token, consumer, &block)
      @people = People.new(token, consumer, &block)
    end
  end
end

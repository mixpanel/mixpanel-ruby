require File.join(File.dirname(__FILE__), 'mixpanel/people.rb')
require File.join(File.dirname(__FILE__), 'mixpanel/events.rb')

class Mixpanel < MixpanelEvents
  attr_reader :people
  def initialize(token, consumer=nil, &block)
    super(token, consumer, &block)
    @people = MixpanelPeople.new(token, consumer, &block)
  end

  private

  class BlockConsumer
    def initialize(block)
      @block = block
    end

    def send(message)
      @block.call(:profile_update, message)
    end
  end
end

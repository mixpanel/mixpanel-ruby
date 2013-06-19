require File.join(File.dirname(__FILE__), 'mixpanel/people.rb')
require File.join(File.dirname(__FILE__), 'mixpanel/events.rb')

class Mixpanel < MixpanelEvents
  attr_reader :people
  def initialize(token, consumer=nil, &block)
    if block
      consumer = BlockConsumer.new(block)
    elsif not consumer
      consumer = MixpanelConsumer.new
    end
    super(token, consumer)
    @people = MixpanelPeople.new(token, consumer)
  end

  private

  class BlockConsumer
    def initialize(block)
      @block = block
    end

    def send_profile_update(message)
      @block.call(:profile_update, message)
    end

    def send_event(message)
      @block.call(:event, message)
    end
  end
end

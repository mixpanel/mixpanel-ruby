require File.join(File.dirname(__FILE__), 'mixpanel/people.rb')
require File.join(File.dirname(__FILE__), 'mixpanel/events.rb')

class Mixpanel < MixpanelEvents
  attr_reader :people
  def initialize(token, consumer=nil)
    super(token, consumer)
    @people = MixpanelPeople.new(token, consumer)
  end
end

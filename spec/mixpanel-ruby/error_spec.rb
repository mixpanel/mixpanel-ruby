require 'spec_helper'
require 'mixpanel-ruby/error.rb'
require 'mixpanel-ruby/events.rb'

class TestErrorHandler < Mixpanel::ErrorHandler
  def initialize(log)
    @log = log
  end

  def handle(error)
    @log << error.to_s
  end
end

describe Mixpanel::ErrorHandler do
  it "should respond to #handle`" do
    error_handler = Mixpanel::ErrorHandler.new
    expect(error_handler.respond_to?(:handle)).to be true
  end

  before(:each) do
    @log = []
    @error_handler = TestErrorHandler.new(@log)
  end

  it "should handle errors with custom error_handler" do
    @events = Mixpanel::Events.new('TEST TOKEN', @error_handler) do |type, message|
      raise Mixpanel::MixpanelError
    end

    @events.track('TEST ID', 'Test Event', {})
    expect(@log).to eq(['Mixpanel::MixpanelError'])
  end

  it "should handle errors with custom error_handler with Mixpanel::People" do
    @people = Mixpanel::People.new('TEST TOKEN', @error_handler) do |type, message|
      raise Mixpanel::MixpanelError
    end

    @people.set('TEST ID', {})
    expect(@log).to eq(['Mixpanel::MixpanelError'])
  end
end

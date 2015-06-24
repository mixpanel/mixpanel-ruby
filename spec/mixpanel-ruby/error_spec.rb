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

  context 'without a customer error_handler' do

    before(:each) do
      @tracker = Mixpanel::Tracker.new('TEST TOKEN') do |type, message|
        raise Mixpanel::MixpanelError
      end
    end

    it "should silence errors in track calls" do
      expect {
        expect(@tracker.track('TEST ID', 'Test Event')).to be false
      }.to_not raise_error
    end

    it "should handle errors in import calls" do
      expect {
        expect(@tracker.import('TEST API KEY', 'TEST DISTINCT_ID', 'Test Event')).to be false
      }.to_not raise_error
    end

    it "should handle errors in people calls" do
      expect {
        expect(@tracker.people.set('TEST ID', {})).to be false
      }.to_not raise_error
    end

  end

  context 'with a custom error_handler' do

    before(:each) do
      @log = []
      @error_handler = TestErrorHandler.new(@log)
      @tracker = Mixpanel::Tracker.new('TEST TOKEN', @error_handler) do |type, message|
        raise Mixpanel::MixpanelError
      end
    end

    it "should handle errors in track calls" do
      @tracker.track('TEST ID', 'Test Event', {})
      expect(@log).to eq(['Mixpanel::MixpanelError'])
    end

    it "should handle errors in import calls" do
      @tracker.import('TEST API KEY', 'TEST DISTINCT_ID', 'Test Event')
      expect(@log).to eq(['Mixpanel::MixpanelError'])
    end

    it "should handle errors in people calls" do
      @tracker.people.set('TEST ID', {})
      expect(@log).to eq(['Mixpanel::MixpanelError'])
    end

  end
end

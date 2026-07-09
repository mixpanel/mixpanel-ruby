require 'mixpanel-ruby'
require 'mixpanel-ruby/consumer'

describe 'Mixpanel::Tracker with custom consumer' do
  it 'should properly initialize error_handler when consumer is provided' do
    custom_consumer = Mixpanel::Consumer.new
    tracker = Mixpanel::Tracker.new('TEST_TOKEN', nil, consumer: custom_consumer)

    # Verify error_handler is initialized (not nil)
    expect(tracker.instance_variable_get(:@error_handler)).not_to be_nil
    expect(tracker.instance_variable_get(:@error_handler)).to be_a(Mixpanel::ErrorHandler)
  end

  it 'should use provided error_handler when consumer is provided' do
    custom_error_handler = Mixpanel::ErrorHandler.new
    custom_consumer = Mixpanel::Consumer.new
    tracker = Mixpanel::Tracker.new('TEST_TOKEN', custom_error_handler, consumer: custom_consumer)

    # Verify the provided error_handler is used
    expect(tracker.instance_variable_get(:@error_handler)).to eq(custom_error_handler)
  end

  it 'should handle errors gracefully when consumer is provided' do
    # Create a consumer that will raise an error
    failing_consumer = Mixpanel::Consumer.new
    allow(failing_consumer).to receive(:send!).and_raise(Mixpanel::ConnectionError.new("Test error"))

    tracker = Mixpanel::Tracker.new('TEST_TOKEN', nil, consumer: failing_consumer)

    # This should not raise - error should be handled by error_handler
    result = tracker.track('user123', 'Test Event')
    expect(result).to be false
  end
end

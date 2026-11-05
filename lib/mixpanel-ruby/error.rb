module Mixpanel

  # Mixpanel specific errors that are thrown in the gem.
  # In the default consumer we catch all errors and raise
  # Mixpanel specific errors that can be handled using a
  # custom error handler.
  class MixpanelError < StandardError
  end
  
  class ConnectionError < MixpanelError
  end
  
  class ServerError < MixpanelError
  end

  # Raised directly to the caller (never passed to the ErrorHandler) when a
  # hierarchical groups tracker is asked for a profile operation that
  # hierarchical groups projects do not support, such as People#increment,
  # People#append or People#track_charge. It signals a mistake in the calling
  # code rather than a delivery failure.
  class UnsupportedOperationError < MixpanelError
  end

  # Raised directly to the caller (never passed to the ErrorHandler) when a
  # hierarchical groups tracker builds a group profile update without
  # knowing its company. Use Tracker#for_company to bind one.
  class CompanyRequiredError < MixpanelError
  end


  # The default behavior of the gem is to silence all errors
  # thrown in the consumer.  If you wish to handle MixpanelErrors
  # yourself you can pass an instance of a class that extends
  # Mixpanel::ErrorHandler to Mixpanel::Tracker on initialize.
  #
  #    require 'logger'
  #
  #    class MyErrorHandler < Mixpanel::ErrorHandler
  #
  #      def initialize
  #        @logger = Logger.new('mylogfile.log')
  #        @logger.level = Logger::ERROR
  #      end
  #    
  #      def handle(error)
  #        logger.error "#{error.inspect}\n Backtrace: #{error.backtrace}"
  #      end
  #
  #    end
  #
  #    my_error_handler = MyErrorHandler.new
  #    tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN, my_error_handler)
  class ErrorHandler

    # Override #handle to customize error handling
    def handle(error)
      false
    end
  end
end

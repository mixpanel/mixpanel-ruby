module Mixpanel

  # Mixpanel specific errors that are thrown in the gem.
  # In the default consumer we catch all errors and raise
  # Mixpanel specific errors that can be handled in a custom
  # Error handler.
  class MixpanelError < StandardError
  end
  
  class ConnectionError < MixpanelError
  end
  
  class ServerError < MixpanelError
  end


  # The default behavior of the gem is to silence all errors
  # thrown in the consumer.  If you wish to handle MixpanelErrors
  # your self you should pass a class that extends ErrorHandler to
  # the Tracker on initialize:
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
  #       end
  #
  #     end
  #
  #    my_error_handler = MyErrorHandler.new
  #    tracker = Mixpanel::Tracker.new(YOUR_MIXPANEL_TOKEN, my_error_handler)
  class ErrorHandler

    def handle(error)
      # Override this method to customize error handling within mixpanel-ruby        
    end
  end
end

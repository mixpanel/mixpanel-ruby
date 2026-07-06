module Mixpanel
  # Service account credentials for server-to-server authentication
  # This is the recommended authentication method over API keys
  class ServiceAccountCredentials
    attr_reader :username, :secret, :project_id

    # Create service account credentials
    # @param username [String] Service account username
    # @param secret [String] Service account secret
    # @param project_id [String, Integer] Mixpanel project ID (accepts string or integer)
    def initialize(username, secret, project_id)
      raise ArgumentError, 'username is required' if username.nil? || username.empty?
      raise ArgumentError, 'secret is required' if secret.nil? || secret.empty?
      raise ArgumentError, 'project_id is required' if project_id.nil?

      # Convert project_id to string if it's an integer (Mixpanel dashboard shows numeric IDs)
      project_id = project_id.to_s if project_id.is_a?(Integer)
      raise ArgumentError, 'project_id is required' if project_id.empty?

      @username = username
      @secret = secret
      @project_id = project_id
    end

    # JSON serialization support - called automatically by JSON.generate/to_json
    #
    # SECURITY NOTE: The secret IS included in the serialized output because it's
    # needed by the Consumer for HTTP Basic Auth. This means the secret will be
    # present in message payloads passed to custom sinks, BufferedConsumer, or
    # async executors. Do not log or persist these messages in plaintext.
    def as_json(options = nil)
      {
        'username' => @username,
        'secret' => @secret,
        'project_id' => @project_id
      }
    end

    # Explicit to_json method for direct .to_json calls
    def to_json(*args)
      as_json.to_json(*args)
    end
  end
end

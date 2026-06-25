module Mixpanel
  # Service account credentials for server-to-server authentication
  # This is the recommended authentication method over API keys
  class ServiceAccountCredentials
    attr_reader :username, :secret, :project_id

    # Create service account credentials
    # @param username [String] Service account username
    # @param secret [String] Service account secret
    # @param project_id [String] Mixpanel project ID
    def initialize(username, secret, project_id)
      raise ArgumentError, 'username is required' if username.nil? || username.empty?
      raise ArgumentError, 'secret is required' if secret.nil? || secret.empty?
      raise ArgumentError, 'project_id is required' if project_id.nil? || project_id.empty?

      @username = username
      @secret = secret
      @project_id = project_id
    end

    # JSON serialization support - called automatically by JSON.generate/to_json
    def as_json(options = nil)
      {
        'username' => @username,
        'secret' => @secret,
        'project_id' => @project_id
      }
    end
  end
end

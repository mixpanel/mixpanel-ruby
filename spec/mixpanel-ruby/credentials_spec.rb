require 'mixpanel-ruby'

describe Mixpanel::ServiceAccountCredentials do
  describe '#initialize' do
    it 'creates credentials with valid parameters' do
      credentials = Mixpanel::ServiceAccountCredentials.new('user', 'secret', 'project123')
      expect(credentials.username).to eq('user')
      expect(credentials.secret).to eq('secret')
      expect(credentials.project_id).to eq('project123')
    end

    it 'raises ArgumentError when username is nil' do
      expect {
        Mixpanel::ServiceAccountCredentials.new(nil, 'secret', 'project123')
      }.to raise_error(ArgumentError, 'username is required')
    end

    it 'raises ArgumentError when username is empty' do
      expect {
        Mixpanel::ServiceAccountCredentials.new('', 'secret', 'project123')
      }.to raise_error(ArgumentError, 'username is required')
    end

    it 'raises ArgumentError when secret is nil' do
      expect {
        Mixpanel::ServiceAccountCredentials.new('user', nil, 'project123')
      }.to raise_error(ArgumentError, 'secret is required')
    end

    it 'raises ArgumentError when secret is empty' do
      expect {
        Mixpanel::ServiceAccountCredentials.new('user', '', 'project123')
      }.to raise_error(ArgumentError, 'secret is required')
    end

    it 'raises ArgumentError when project_id is nil' do
      expect {
        Mixpanel::ServiceAccountCredentials.new('user', 'secret', nil)
      }.to raise_error(ArgumentError, 'project_id is required')
    end

    it 'raises ArgumentError when project_id is empty' do
      expect {
        Mixpanel::ServiceAccountCredentials.new('user', 'secret', '')
      }.to raise_error(ArgumentError, 'project_id is required')
    end
  end

  describe 'JSON serialization' do
    it 'serializes to JSON correctly' do
      credentials = Mixpanel::ServiceAccountCredentials.new('user', 'secret', 'project123')
      json_str = credentials.to_json
      parsed = JSON.parse(json_str)
      # Secret should NOT be serialized for security
      expect(parsed).to eq({
        'username' => 'user',
        'project_id' => 'project123'
      })
      # But secret is still accessible on the object
      expect(credentials.secret).to eq('secret')
    end

    it 'survives JSON round-trip' do
      credentials = Mixpanel::ServiceAccountCredentials.new('user', 'secret', 'project123')
      message = {'credentials' => credentials}.to_json
      decoded = JSON.load(message)
      # Secret should NOT be in serialized JSON for security
      expect(decoded['credentials']).to eq({
        'username' => 'user',
        'project_id' => 'project123'
      })
    end
  end
end

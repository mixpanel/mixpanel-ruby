require 'mixpanel-ruby'

if __FILE__ == $0
  # Replace this with the token from your project settings
  DEMO_TOKEN = '072f77c15bd04a5d0044d3d76ced7fea'
  mixpanel_tracker = Mixpanel::Tracker.new(DEMO_TOKEN)
  mixpanel_tracker.track('ID', 'Script run')
end

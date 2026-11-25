require 'spec_helper'
require 'mixpanel-ruby'

describe 'Hierarchical groups' do
  let(:token) { 'TEST TOKEN' }

  before(:each) do
    # Keep the credentials-with-a-sink and deprecation warnings out of the output.
    allow_any_instance_of(Mixpanel::Tracker).to receive(:warn)
    @time_now = Time.parse('Jun 6 1972, 16:23:04')
    allow(Time).to receive(:now).and_return(@time_now)

    @log = []
    sink = proc { |type, message| @log << [type, JSON.load(message)] }
    @hg = Mixpanel::Tracker.new(token, hierarchical_groups: true, &sink)
    @legacy = Mixpanel::Tracker.new(token, &sink)
    @credentials = Mixpanel::ServiceAccountCredentials.new('user', 'secret', '123')
  end

  def identity(**values)
    Mixpanel::Identity.new(**values)
  end

  def user_in_acme
    identity(user_id: 'user_123', company_id: 'acme')
  end

  def last_type
    @log.last[0]
  end

  def last_data
    @log.last[1]['data']
  end

  def last_properties
    last_data['properties']
  end

  describe 'errors' do
    it 'are all Mixpanel::MixpanelErrors' do
      [Mixpanel::InvalidIdentityError, Mixpanel::UnsupportedOperationError,
       Mixpanel::CompanyRequiredError].each do |error|
        expect(error.superclass).to eq(Mixpanel::MixpanelError)
        expect(error.ancestors).not_to include(ArgumentError)
      end
    end

    it 'raises identity misuse to the caller rather than the error handler' do
      handled = []
      handler = Class.new(Mixpanel::ErrorHandler) { define_method(:handle) { |e| handled << e } }.new
      tracker = Mixpanel::Tracker.new(token, handler, hierarchical_groups: true) { |*| }
      expect { tracker.track(identity(user_id: 'a|b', company_id: 'acme'), 'Signup') }
        .to raise_error(Mixpanel::InvalidIdentityError, /must not contain '\|'/)
      expect(handled).to be_empty
    end
  end

  describe 'Mixpanel::Identity' do
    it 'rejects empty values' do
      # An empty string is a caller error; nil simply leaves the value unset.
      expect { identity(user_id: '') }.to raise_error(Mixpanel::InvalidIdentityError, /user_id/)
      expect { identity(company_id: '') }.to raise_error(Mixpanel::InvalidIdentityError, /company_id/)
      expect { identity(device_id: '') }.to raise_error(Mixpanel::InvalidIdentityError, /device_id/)
      expect { identity(distinct_id: '') }.to raise_error(Mixpanel::InvalidIdentityError, /distinct_id/)
    end

    it 'accepts String and Integer ids and sends them as strings' do
      id = identity(distinct_id: 0, user_id: 42, company_id: 7, device_id: 'dev')

      expect(id.to_properties).to eq('distinct_id' => 0, '$user_id' => 42, '$company_id' => 7, '$device_id' => 'dev')
      @hg.track(id, 'event')
      expect(last_properties['$user_id']).to eq('42')
      expect(last_properties['$company_id']).to eq('7')
      expect(last_properties['distinct_id']).to eq('0')
      expect(last_properties['$device_id']).to eq('dev')
    end

    it 'sends Integer identity ids as strings without hierarchical groups' do
      @legacy.track(identity(user_id: 42, device_id: 9), 'event')
      expect(last_properties['$user_id']).to eq('42')
      expect(last_properties['$device_id']).to eq('9')
    end

    it 'sends an Integer identity distinct id as a string' do
      @legacy.track(identity(distinct_id: 5), 'event')
      expect(last_properties['distinct_id']).to eq('5')
    end

    it 'sends an Integer identity distinct id as a string on profile updates' do
      @legacy.people.set(identity(distinct_id: 123), {'plan' => 'pro'})
      expect(last_data['$distinct_id']).to eq('123')
      expect(last_data['$set']).to include('plan' => 'pro')
    end

    it 'puts an Integer identity distinct id in the flag context as a string' do
      expect(identity(distinct_id: 5).to_flag_context).to eq('distinct_id' => '5')
    end

    it 'sends an Integer device id as a string' do
      @hg.track(identity(user_id: 'user_123', company_id: 'acme', device_id: 9), 'event')
      expect(last_properties['$device_id']).to eq('9')
    end

    it 'sends raw properties as given' do
      @legacy.track('user_123', 'event', {'$user_id' => 42, '$device_id' => 9})
      expect(last_properties).to include('$user_id' => 42, '$device_id' => 9)
      @hg.track(identity(device_id: 'dev'), 'event', {'$user_id' => 42, '$company_id' => 7})
      expect(last_properties).to include('$user_id' => 42, '$company_id' => 7, '$device_id' => 'dev')
    end

    it 'accepts a | in ids, which only hierarchical groups trackers refuse' do
      id = identity(user_id: 'a|b', company_id: 'c|d', device_id: 'e|f')
      expect(id.user_id).to eq('a|b')
      @legacy.track(identity(user_id: 'a|b', device_id: 'e|f'), 'event')
      expect(last_properties).to include('$user_id' => 'a|b', '$device_id' => 'e|f')
    end

    it 'rejects a user or company id of only whitespace' do
      ['  ', ' ', "\t\n"].each do |blank|
        expect { identity(user_id: blank, company_id: 'acme') }.to raise_error(Mixpanel::InvalidIdentityError, /user_id/)
        expect { identity(user_id: 'user_123', company_id: blank) }.to raise_error(Mixpanel::InvalidIdentityError, /company_id/)
      end
    end

    it 'keeps ids with surrounding whitespace as given' do
      @hg.track(identity(user_id: ' user_123 ', company_id: ' acme'), 'event')
      expect(last_properties).to include('$user_id' => ' user_123 ', '$company_id' => ' acme')
    end

    it 'rejects ids that are not a String or an Integer' do
      %i[distinct_id user_id company_id device_id].each do |name|
        [true, false, 1.5, ['a'], {'a' => 1}, :a].each do |value|
          expect { identity(name => value) }.to raise_error(Mixpanel::InvalidIdentityError, /#{name}/)
        end
      end
    end

    it 'needs at least one value' do
      expect { Mixpanel::Identity.new }.to raise_error(Mixpanel::InvalidIdentityError)
      expect { identity(user_id: nil, company_id: nil) }.to raise_error(Mixpanel::InvalidIdentityError)
    end

    it 'treats nil as unset' do
      id = identity(user_id: 'user_123', device_id: nil)

      expect(id.user_id).to eq('user_123')
      expect(id.device_id).to be_nil
      expect(id.to_properties).to eq('$user_id' => 'user_123')
    end

    it 'is frozen and hierarchical only when it names a company' do
      expect(user_in_acme).to be_frozen
      expect(user_in_acme.user_id).to be_frozen
      expect(user_in_acme).to be_hierarchical
      expect(identity(user_id: 'user_123', device_id: 'd')).not_to be_hierarchical
    end

    it 'has a readable string form and value equality' do
      expect(user_in_acme.to_s).to eq('Mixpanel::Identity{user_id=user_123, company_id=acme}')
      expect(user_in_acme).to eq(user_in_acme)
      expect(user_in_acme.hash).to eq(user_in_acme.hash)
      expect(user_in_acme).not_to eq(identity(user_id: 'user_123', company_id: 'other'))
    end

    it 'builds a flag context' do
      id = identity(user_id: 'user_123', company_id: 'acme', device_id: 'device_abc')

      expect(id.to_flag_context(groups: { 'department' => 'finance' },
                                custom_properties: { 'plan' => 'enterprise' })).to eq(
        '$user_id' => 'user_123',
        '$company_id' => 'acme',
        'device_id' => 'device_abc',
        'department' => 'finance',
        'custom_properties' => { 'plan' => 'enterprise' }
      )
    end

    it 'builds a flag context with ids as strings' do
      expect(identity(user_id: 42, company_id: 7, device_id: 9).to_flag_context).to eq(
        '$user_id' => '42', '$company_id' => '7', 'device_id' => '9'
      )
    end

    it 'builds a flag context from a plain distinct id' do
      expect(identity(distinct_id: 'user_123').to_flag_context).to eq('distinct_id' => 'user_123')
    end
  end

  describe 'events' do
    it 'refuses an identity whose user or company id contains a |' do
      [identity(user_id: 'a|b', company_id: 'acme'), identity(user_id: 'user_123', company_id: 'a|b'),
       identity(company_id: 'a|b')].each do |id|
        expect { @hg.track(id, 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError, /must not contain '\|'/)
      end
      expect(@log).to be_empty
    end

    it 'accepts a | in a device id or a plain distinct id' do
      @hg.track(identity(device_id: 'a|b'), 'Signup')
      expect(last_properties['$device_id']).to eq('a|b')
      @hg.track('a|b', 'Signup')
      expect(last_properties['distinct_id']).to eq('a|b')
    end

    it 'refuses a combined distinct id whose company or user contains a |' do
      expect { @hg.track('$company:a|b|$user:c', 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError, /must not contain '\|'/)
      expect { @hg.track('$company:a|$user:b|c', 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError, /must not contain '\|'/)
      expect(@log).to be_empty
      @legacy.track('$company:a|$user:b|c', 'Signup')
      expect(last_properties['distinct_id']).to eq('$company:a|$user:b|c')
    end

    it 'sends user and company without a distinct id' do
      @hg.track(user_in_acme, 'Signup')

      expect(last_type).to eq(:event)
      expect(last_properties['$user_id']).to eq('user_123')
      expect(last_properties['$company_id']).to eq('acme')
      expect(last_properties).not_to have_key('distinct_id')
      expect(last_properties).not_to have_key('$device_id')
      expect(last_properties['token']).to eq(token)
    end

    it 'sends a device id' do
      @hg.track(identity(user_id: 'user_123', company_id: 'acme', device_id: 'device_abc'), 'Signup')

      expect(last_properties['$device_id']).to eq('device_abc')
      expect(last_properties).not_to have_key('distinct_id')
    end

    it 'sends a company-only event' do
      @hg.track(identity(company_id: 'acme'), 'Renewed')

      expect(last_properties['$company_id']).to eq('acme')
      expect(last_properties).not_to have_key('$user_id')
      expect(last_properties).not_to have_key('distinct_id')
    end

    it 'sends a distinct id identity as distinct_id on a legacy tracker' do
      @legacy.track(identity(distinct_id: 'user_123'), 'Signup')

      expect(last_properties['distinct_id']).to eq('user_123')
      expect(last_properties).not_to have_key('$user_id')
      expect(last_properties).not_to have_key('$company_id')
    end

    it 'lets identity keys replace caller properties and keeps the others' do
      caller_properties = {'$company_id' => 'wrong', 'plan' => 'enterprise'}
      @hg.track(user_in_acme, 'Signup', caller_properties)

      expect(last_properties['$company_id']).to eq('acme')
      expect(last_properties['plan']).to eq('enterprise')
      expect(caller_properties['$company_id']).to eq('wrong')
    end

    it 'imports a hierarchical event' do
      tracker = Mixpanel::Tracker.new(token, credentials: @credentials, hierarchical_groups: true) do |type, message|
        @log << [type, JSON.load(message)]
      end
      allow(tracker).to receive(:warn)

      tracker.import_events(user_in_acme, 'Signup', {'time' => 1369353600})
      expect(last_type).to eq(:import)
      expect(last_properties['$user_id']).to eq('user_123')
      expect(last_properties['$company_id']).to eq('acme')
      expect(last_properties).not_to have_key('distinct_id')

      tracker.import('API_KEY', user_in_acme, 'Signup')
      expect(last_type).to eq(:import)
      expect(last_properties['$company_id']).to eq('acme')
    end

    it 'accepts a user and device without a company for simplified id merge' do
      # $user_id with $device_id is the standard non-hierarchical server-side identity.
      @legacy.track(identity(user_id: 'user_123', device_id: 'device_abc'), 'Signup')

      expect(last_properties['$user_id']).to eq('user_123')
      expect(last_properties['$device_id']).to eq('device_abc')
      expect(last_properties).not_to have_key('distinct_id')
      expect(last_properties).not_to have_key('$company_id')
    end

    it 'sends a user without a company as given on a hierarchical tracker' do
      @hg.track(identity(user_id: 'user_123'), 'Signup')

      expect(last_properties['$user_id']).to eq('user_123')
      expect(last_properties).not_to have_key('$company_id')
    end

    it 'allows a user with a device but no company on a hierarchical tracker' do
      # Mixpanel ignores the user id and keeps the event under the device, which later
      # links to the company-scoped user. Recoverable, so the library does not refuse it.
      @hg.track(identity(user_id: 'user_123', device_id: 'device_abc'), 'Signup')

      expect(last_properties['$device_id']).to eq('device_abc')
      expect(last_properties).not_to have_key('$company_id')
    end

    it 'sends anonymous device events on both kinds of tracker' do
      [@hg, @legacy].each do |tracker|
        tracker.track(identity(device_id: 'device_abc'), 'Page View')

        expect(last_properties['$device_id']).to eq('device_abc')
        expect(last_properties).not_to have_key('distinct_id')
        expect(last_properties).not_to have_key('$user_id')
        expect(last_properties).not_to have_key('$company_id')
      end
    end

    it 'passes a combined distinct id through' do
      # Ingestion parses $company:{company}|$user:{user} back into $company_id and $user_id.
      combined = '$company:acme|$user:user_123'
      @hg.track(combined, 'Signup')
      @hg.track(identity(distinct_id: combined), 'Signup')

      @log.each do |_, message|
        expect(message['data']['properties']['distinct_id']).to eq(combined)
        expect(message['data']['properties']).not_to have_key('$user_id')
      end
    end

    it 'refuses a combined distinct id whose $company_id or $user_id property differs' do
      tracker = Mixpanel::Tracker.new(token, credentials: @credentials, hierarchical_groups: true) do |type, message|
        @log << [type, JSON.load(message)]
      end
      combined = '$company:c6|$user:u6'

      expect { @hg.track(combined, 'Signup', {'$company_id' => 'zz6'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, 'distinct_id $company:c6|$user:u6 names company c6, but $company_id is zz6. Nothing sent')
      expect { @hg.track(combined, 'Signup', {'$user_id' => 'zz6'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, 'distinct_id $company:c6|$user:u6 names user u6, but $user_id is zz6. Nothing sent')
      expect { @hg.track(combined, 'Signup', {:'$company_id' => 'zz6'}) }.to raise_error(Mixpanel::InvalidIdentityError)
      expect { tracker.import_events(combined, 'Signup', {'$company_id' => 'zz6'}) }.to raise_error(Mixpanel::InvalidIdentityError)
      expect { tracker.import('API_KEY', combined, 'Signup', {'$user_id' => 'zz6'}) }.to raise_error(Mixpanel::InvalidIdentityError)
      expect(@log).to be_empty
    end

    it 'sends a combined distinct id with matching $company_id and $user_id properties unchanged' do
      @hg.track('$company:7|$user:8', 'Signup', {'$company_id' => 7, '$user_id' => '8', 'plan' => 'x'})

      expect(last_properties).to include('distinct_id' => '$company:7|$user:8', '$company_id' => 7,
                                         '$user_id' => '8', 'plan' => 'x')
    end

    describe 'with a distinct_id property replacing the argument' do
      let(:tracker) do
        Mixpanel::Tracker.new(token, credentials: @credentials, hierarchical_groups: true) do |type, message|
          @log << [type, JSON.load(message)]
        end
      end

      def url_properties(url)
        JSON.parse(Base64.urlsafe_decode64(url[/data=([^&]*)/, 1]))['properties']
      end

      it 'checks the final distinct_id and sends a consistent override' do
        properties = {'distinct_id' => '$company:b|$user:u', '$company_id' => 'b'}
        expected = {'distinct_id' => '$company:b|$user:u', '$company_id' => 'b'}

        @hg.track('$company:a|$user:u', 'Signup', properties)
        expect(last_properties).to include(expected)
        tracker.import_events('$company:a|$user:u', 'Signup', properties)
        expect(last_properties).to include(expected)
        tracker.import('API_KEY', '$company:a|$user:u', 'Signup', properties)
        expect(last_properties).to include(expected)
        expect(url_properties(@hg.generate_tracking_url('$company:a|$user:u', 'Signup', properties))).to include(expected)
      end

      it 'refuses an override that conflicts with $company_id even when the argument matches' do
        properties = {'distinct_id' => '$company:b|$user:u', '$company_id' => 'a'}
        message = 'distinct_id $company:b|$user:u names company b, but $company_id is a. Nothing sent'

        expect { @hg.track('$company:a|$user:u', 'Signup', properties) }.to raise_error(Mixpanel::InvalidIdentityError, message)
        expect { tracker.import_events('$company:a|$user:u', 'Signup', properties) }.to raise_error(Mixpanel::InvalidIdentityError, message)
        expect { tracker.import('API_KEY', '$company:a|$user:u', 'Signup', properties) }.to raise_error(Mixpanel::InvalidIdentityError, message)
        expect { @hg.generate_tracking_url('$company:a|$user:u', 'Signup', properties) }.to raise_error(Mixpanel::InvalidIdentityError, message)
        expect(@log).to be_empty
      end

      it 'refuses an override with a blank company or user' do
        {'$company: |$user:u' => 'company', '$company:a|$user:' => 'user'}.each do |distinct_id, part|
          properties = {'distinct_id' => distinct_id}
          message = "distinct_id #{distinct_id.inspect} names a blank #{part}. Nothing sent"

          expect { @hg.track('$company:a|$user:u', 'Signup', properties) }.to raise_error(Mixpanel::InvalidIdentityError, message)
          expect { tracker.import_events('$company:a|$user:u', 'Signup', properties) }.to raise_error(Mixpanel::InvalidIdentityError, message)
          expect { tracker.import('API_KEY', '$company:a|$user:u', 'Signup', properties) }.to raise_error(Mixpanel::InvalidIdentityError, message)
          expect { @hg.generate_tracking_url('$company:a|$user:u', 'Signup', properties) }.to raise_error(Mixpanel::InvalidIdentityError, message)
        end
        expect(@log).to be_empty
      end
    end

    it 'refuses a combined distinct id with a blank company or user on events' do
      tracker = Mixpanel::Tracker.new(token, credentials: @credentials, hierarchical_groups: true) do |type, message|
        @log << [type, JSON.load(message)]
      end
      {
        '$company:|$user:u' => 'company', '$company: |$user:u' => 'company', '$company:|$user:' => 'company',
        '$company: |$user:' => 'company', '$company: |$user:  ' => 'company',
        '$company:c|$user:' => 'user', '$company:c|$user:  ' => 'user'
      }.each do |distinct_id, part|
        message = "distinct_id #{distinct_id.inspect} names a blank #{part}. Nothing sent"
        expect { @hg.track(distinct_id, 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError, message)
        expect { tracker.import_events(distinct_id, 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError, message)
        expect { tracker.import('API_KEY', distinct_id, 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError, message)
        expect { @hg.generate_tracking_url(distinct_id, 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError, message)
      end
      expect(@log).to be_empty
    end

    it 'refuses an identity whose combined distinct id has a blank company or user on events' do
      tracker = Mixpanel::Tracker.new(token, credentials: @credentials, hierarchical_groups: true) do |type, message|
        @log << [type, JSON.load(message)]
      end
      {
        '$company:|$user:u' => 'company', '$company: |$user:u' => 'company', '$company:|$user:' => 'company',
        '$company: |$user:' => 'company', '$company: |$user:  ' => 'company',
        '$company:c|$user:' => 'user', '$company:c|$user:  ' => 'user'
      }.each do |distinct_id, part|
        message = "distinct_id #{distinct_id.inspect} names a blank #{part}. Nothing sent"
        [identity(distinct_id: distinct_id), identity(distinct_id: distinct_id, user_id: 'u', company_id: 'c')].each do |id|
          expect { @hg.track(id, 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError, message)
          expect { tracker.import_events(id, 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError, message)
          expect { tracker.import('API_KEY', id, 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError, message)
          expect { @hg.generate_tracking_url(id, 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError, message)
        end
      end
      expect(@log).to be_empty
    end

    it 'refuses an identity whose combined distinct id names a different user or company on events' do
      tracker = Mixpanel::Tracker.new(token, credentials: @credentials, hierarchical_groups: true) do |type, message|
        @log << [type, JSON.load(message)]
      end
      {
        identity(distinct_id: '$company:acme|$user:old', user_id: 'new', company_id: 'acme') =>
          'distinct_id $company:acme|$user:old names user old, but user_id is new. Nothing sent',
        identity(distinct_id: '$company:acme|$user:u', user_id: 'u', company_id: 'other') =>
          'distinct_id $company:acme|$user:u names company acme, but company_id is other. Nothing sent',
        identity(distinct_id: '$company:acme|$user:old', user_id: 'new') =>
          'distinct_id $company:acme|$user:old names user old, but user_id is new. Nothing sent',
        identity(distinct_id: '$company:acme|$user:u', company_id: 7) =>
          'distinct_id $company:acme|$user:u names company acme, but company_id is 7. Nothing sent'
      }.each do |id, message|
        expect { @hg.track(id, 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError, message)
        expect { tracker.import_events(id, 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError, message)
        expect { tracker.import('API_KEY', id, 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError, message)
        expect { @hg.generate_tracking_url(id, 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError, message)
      end
      expect(@log).to be_empty
    end

    it 'sends an identity whose combined distinct id agrees with its user and company ids' do
      @hg.track(identity(distinct_id: '$company:7|$user:42', user_id: 42, company_id: 7), 'Signup')
      expect(last_properties).to include('distinct_id' => '$company:7|$user:42', '$user_id' => '42', '$company_id' => '7')
      @hg.track(identity(distinct_id: '$company:acme|$user:u', user_id: 'u'), 'Signup')
      expect(last_properties).to include('distinct_id' => '$company:acme|$user:u', '$user_id' => 'u')
      @hg.track(identity(distinct_id: '$company:acme|$user:u', company_id: 'acme'), 'Signup')
      expect(last_properties).to include('distinct_id' => '$company:acme|$user:u', '$company_id' => 'acme')
    end

    it 'sends an identity whose combined distinct id disagrees with its ids without hierarchical groups' do
      @legacy.track(identity(distinct_id: '$company:acme|$user:old', user_id: 'new'), 'Signup')
      expect(last_properties).to include('distinct_id' => '$company:acme|$user:old', '$user_id' => 'new')
      @legacy.people.set(identity(distinct_id: '$company:acme|$user:old', user_id: 'new'), {'role' => 'admin'})
      expect(last_type).to eq(:profile_update)
      expect(last_data['$distinct_id']).to eq('$company:acme|$user:old')
    end

    it 'sends an identity whose distinct id is combined with non-blank parts, or not combined, as given' do
      ['$company:c|$user: u ', '$company:acme', '$device:abc', 'user_123'].each do |distinct_id|
        @hg.track(identity(distinct_id: distinct_id), 'Signup')
        expect(last_properties['distinct_id']).to eq(distinct_id)
      end
    end

    it 'sends an identity whose combined distinct id has a blank part without hierarchical groups' do
      ['$company:|$user:u', '$company: |$user:  ', '$company:c|$user:'].each do |distinct_id|
        @legacy.track(identity(distinct_id: distinct_id), 'Signup')
        expect(last_properties['distinct_id']).to eq(distinct_id)
      end
    end

    it 'sends a combined distinct id with non-blank parts, and a non-combined id, as given' do
      ['$company:c|$user: u ', '$company:acme', '$device:abc', 'user_123'].each do |distinct_id|
        @hg.track(distinct_id, 'Signup')
        expect(last_properties['distinct_id']).to eq(distinct_id)
      end
    end

    it 'sends a plain distinct id with any $company_id and $user_id properties unchanged' do
      @hg.track('user_123', 'Signup', {'$company_id' => 'acme', '$user_id' => 'other'})
      expect(last_properties).to include('distinct_id' => 'user_123', '$company_id' => 'acme', '$user_id' => 'other')
    end

    it 'sends a conflicting or blank combined distinct id unchanged without hierarchical groups' do
      @legacy.track('$company:c6|$user:u6', 'Signup', {'$company_id' => 'zz6', '$user_id' => 'zz6'})
      expect(last_properties).to include('distinct_id' => '$company:c6|$user:u6', '$company_id' => 'zz6', '$user_id' => 'zz6')
      ['$company: |$user:  ', '$company:|$user:', '$company:c|$user:'].each do |distinct_id|
        @legacy.track(distinct_id, 'Signup')
        expect(last_properties['distinct_id']).to eq(distinct_id)
      end
    end

    it 'never refuses a raw distinct id' do
      tracker = Mixpanel::Tracker.new(token, credentials: @credentials, hierarchical_groups: true) do |type, message|
        @log << [type, JSON.load(message)]
      end

      @hg.track('user_123', 'Signup')
      expect(last_properties['distinct_id']).to eq('user_123')
      tracker.import_events('user_123', 'Signup')
      expect(last_properties['distinct_id']).to eq('user_123')
      @legacy.track('user_123', 'Signup')
      expect(last_properties['distinct_id']).to eq('user_123')
    end

    it 'requires a hierarchical tracker for a hierarchical identity' do
      tracker = Mixpanel::Tracker.new(token, credentials: @credentials) { |*args| @log << args }

      expect { @legacy.track(user_in_acme, 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError, /hierarchical_groups: true/)
      expect { tracker.import_events(user_in_acme, 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError)
      expect { @legacy.track(identity(company_id: 'acme'), 'Renewed') }.to raise_error(Mixpanel::InvalidIdentityError)
      expect(@log).to be_empty
    end

    it 'raises caller errors directly instead of passing them to the error handler' do
      handler = Mixpanel::ErrorHandler.new
      tracker = Mixpanel::Tracker.new(token, handler) { |*args| }
      expect(handler).not_to receive(:handle)

      expect { tracker.track(user_in_acme, 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError)
    end
  end

  describe 'generate_tracking_url' do
    def url_properties(url)
      data = url[/data=([^&]*)/, 1]
      JSON.parse(Base64.urlsafe_decode64(data))['properties']
    end

    it 'applies an identity like track' do
      url = @hg.generate_tracking_url(user_in_acme, 'Signup', {'$company_id' => 'wrong', 'plan' => 'x'})
      @hg.track(user_in_acme, 'Signup', {'$company_id' => 'wrong', 'plan' => 'x'})

      expect(url_properties(url)).to eq(last_properties)
      expect(url_properties(url)).to include('$user_id' => 'user_123', '$company_id' => 'acme', 'plan' => 'x')
      expect(url_properties(url)).not_to have_key('distinct_id')
    end

    it 'sends Integer user and company ids as strings' do
      properties = url_properties(@hg.generate_tracking_url(identity(user_id: 3190316, company_id: 3190317), 'Signup'))
      expect(properties).to include('$user_id' => '3190316', '$company_id' => '3190317')
    end

    it 'applies a distinct id identity on a legacy tracker' do
      properties = url_properties(@legacy.generate_tracking_url(identity(distinct_id: 'user_123'), 'Signup'))
      expect(properties['distinct_id']).to eq('user_123')
    end

    it 'requires a hierarchical tracker for a hierarchical identity' do
      expect { @legacy.generate_tracking_url(user_in_acme, 'Signup') }
        .to raise_error(Mixpanel::InvalidIdentityError, /hierarchical_groups: true/)
    end

    it 'refuses a conflicting combined distinct id like track' do
      expect { @hg.generate_tracking_url('$company:c6|$user:u6', 'Signup', {'$company_id' => 'zz6'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, /names company c6, but \$company_id is zz6/)
      expect { @hg.generate_tracking_url('$company: |$user:u6', 'Signup') }.to raise_error(Mixpanel::InvalidIdentityError)
    end

    it 'builds the same url for a string distinct id on both kinds of tracker' do
      properties = {'Circumstances' => 'During test'}
      expect(@hg.generate_tracking_url('TEST_ID', 'event', properties))
        .to eq(@legacy.generate_tracking_url('TEST_ID', 'event', properties))
      expect(url_properties(@legacy.generate_tracking_url('TEST_ID', 'event', properties))).to eq(
        'distinct_id' => 'TEST_ID', 'token' => token, 'time' => (@time_now.to_f * 1000).to_i,
        'mp_lib' => 'ruby', '$lib_version' => Mixpanel::VERSION, 'Circumstances' => 'During test'
      )
    end
  end

  describe 'alias' do
    it 'refuses alias on a hierarchical tracker' do
      expect { @hg.alias('$company:acme|$user:u2', '$company:acme|$user:user_123') }
        .to raise_error(Mixpanel::UnsupportedOperationError, /alias is not supported/)
    end
  end

  describe 'user profiles' do
    it 'refuses $add and $append on a hierarchical tracker' do
      # A hierarchical groups user profile is a group profile, and /groups has no $add or $append.
      error = Mixpanel::UnsupportedOperationError

      expect { @hg.people.increment('user_123', {'logins' => 1}) }.to raise_error(error)
      expect { @hg.people.plus_one('user_123', 'logins') }.to raise_error(error)
      expect { @hg.people.append('user_123', {'plan' => 'pro'}) }.to raise_error(error)
      expect { @hg.people.track_charge('user_123', 9.99) }.to raise_error(error)
      expect { @hg.people.update('$distinct_id' => 'user_123', '$add' => {'logins' => 1}) }.to raise_error(error)
      expect { @hg.people.update('$distinct_id' => 'user_123', '$append' => {'plan' => 'pro'}) }.to raise_error(error)
      expect(@log).to be_empty
    end

    it 'names what is supported when it refuses an operation' do
      expect { @hg.people.increment('user_123', {'logins' => 1}) }.to raise_error(
        Mixpanel::UnsupportedOperationError, /\$add.*increment, plus_one, append and track_charge/)
    end

    it 'refuses an identity for $add and $append on a legacy tracker' do
      id = identity(distinct_id: 'user_123')

      expect { @legacy.people.increment(id, {'logins' => 1}) }.to raise_error(Mixpanel::InvalidIdentityError, /increment/)
      expect { @legacy.people.append(id, {'plan' => 'pro'}) }.to raise_error(Mixpanel::InvalidIdentityError, /append/)
      expect { @legacy.people.track_charge(id, 9.99) }.to raise_error(Mixpanel::InvalidIdentityError)
      expect(@log).to be_empty
    end

    it 'sends supported operations for a combined distinct id to the user group profile' do
      id = '$company:acme|$user:user_123'
      @hg.people.set(id, {'plan' => 'pro'})
      @hg.people.set_once(id, {'plan' => 'pro'})
      @hg.people.delete_user(id)
      @hg.people.union(id, {'tags' => ['a']})
      @hg.people.unset(id, 'plan')

      expect(@log.map(&:first)).to eq([:group_update] * 5)
      @log.each do |_, message|
        data = message['data']
        expect(data).not_to have_key('$distinct_id')
        expect(data['$group_key']).to eq('$user_id')
        expect(data['$group_id']).to eq('user_123')
        expect(data['$company_id']).to eq('acme')
      end
    end

    it 'sends a combined distinct id exactly as the matching identity' do
      id = '$company:acme|$user:user_123'
      params = {'$ignore_time' => true}
      @hg.people.set(id, {'plan' => 'pro'}, '1.2.3.4', params)
      @hg.people.set(identity(distinct_id: id), {'plan' => 'pro'}, '1.2.3.4', params)
      @hg.people.set(user_in_acme, {'plan' => 'pro'}, '1.2.3.4', params)

      expect(@log.length).to eq(3)
      expect(@log[0]).to eq(@log[2])
      expect(@log[1]).to eq(@log[2])
      expect(@log[2][1]['data']['$ip']).to eq('1.2.3.4')
      expect(@log[2][1]['data']['$ignore_time']).to be true
    end

    it 'parses the company up to the first |$user: and the user from the rest' do
      @hg.people.set('$company:a:b|$user:c:$user:d', {'plan' => 'pro'})

      expect(last_data['$company_id']).to eq('a:b')
      expect(last_data['$group_id']).to eq('c:$user:d')
    end

    it 'refuses a combined distinct id whose company or user contains a |' do
      ['$company:a|b|$user:c', '$company:a|$user:c|$user:d', '$company:a|$user:b|c'].each do |id|
        expect { @hg.people.set(id, {'plan' => 'pro'}) }.to raise_error(Mixpanel::InvalidIdentityError, /must not contain '\|'/)
        expect { @hg.people.set(identity(distinct_id: id), {'plan' => 'pro'}) }
          .to raise_error(Mixpanel::InvalidIdentityError, /must not contain '\|'/)
        expect { @hg.people.update('$distinct_id' => id, '$set' => {'plan' => 'pro'}) }
          .to raise_error(Mixpanel::InvalidIdentityError, /must not contain '\|'/)
      end
      expect(@log).to be_empty
    end

    it 'refuses an identity whose user or company id contains a |' do
      [identity(user_id: 'a|b', company_id: 'acme'), identity(user_id: 'user_123', company_id: 'a|b')].each do |id|
        expect { @hg.people.set(id, {'plan' => 'pro'}) }.to raise_error(Mixpanel::InvalidIdentityError, /must not contain '\|'/)
        expect { @hg.people.delete_user(id) }.to raise_error(Mixpanel::InvalidIdentityError, /must not contain '\|'/)
      end
      expect(@log).to be_empty
    end

    it 'refuses $ignore_alias in optional_params' do
      [user_in_acme, '$company:acme|$user:user_123'].each do |user|
        expect { @hg.people.delete_user(user, {'$ignore_alias' => true}) }
          .to raise_error(Mixpanel::UnsupportedOperationError, /\$ignore_alias/)
        expect { @hg.people.set(user, {'plan' => 'pro'}, nil, {:$ignore_alias => false}) }
          .to raise_error(Mixpanel::UnsupportedOperationError, /\$ignore_alias/)
      end
      expect { @hg.people.update('$distinct_id' => '$company:acme|$user:user_123', '$set' => {'a' => 1},
                                 '$ignore_alias' => true) }
        .to raise_error(Mixpanel::UnsupportedOperationError, /\$ignore_alias/)
      expect(@log).to be_empty
    end

    it 'sends $ignore_alias to /engage without hierarchical groups' do
      @legacy.people.delete_user('user_123', {'$ignore_alias' => true})
      expect(last_type).to eq(:profile_update)
      expect(last_data['$ignore_alias']).to be true
    end

    it 'refuses a distinct id that is not a combined one on a hierarchical tracker' do
      [
        'user_123',
        '$company:acme',
        '|$user:user_123',
        '$group:acme|$user:user_123',
        'company:acme|$user:user_123',
        '$user:user_123|$company:acme',
      ].each do |id|
        expect { @hg.people.set(id, {'plan' => 'pro'}) }.to raise_error(Mixpanel::InvalidIdentityError, /user and a company/)
        expect { @hg.people.unset(id, 'plan') }.to raise_error(Mixpanel::InvalidIdentityError, /\$company:\{company\}\|\$user:\{user\}/)
        expect { @hg.people.delete_user(id) }.to raise_error(Mixpanel::InvalidIdentityError, /Mixpanel::Identity/)
        expect { @hg.people.set(identity(distinct_id: id), {'plan' => 'pro'}) }.to raise_error(Mixpanel::InvalidIdentityError)
        expect { @hg.people.update('$distinct_id' => id, '$set' => {'plan' => 'pro'}) }.to raise_error(Mixpanel::InvalidIdentityError)
      end
      expect(@log).to be_empty
    end

    it 'refuses $add and $append before checking the distinct id' do
      expect { @hg.people.increment('$company:acme|$user:user_123', {'logins' => 1}) }
        .to raise_error(Mixpanel::UnsupportedOperationError)
      expect { @hg.people.update('$distinct_id' => 'not combined', '$add' => {'logins' => 1}) }
        .to raise_error(Mixpanel::UnsupportedOperationError)
      expect(@log).to be_empty
    end

    it 'rewrites a generic update with a combined distinct id to the user group profile' do
      @hg.people.update('$distinct_id' => '$company:acme|$user:user_123', '$set' => {'plan' => 'pro'},
                        '$ip' => '1.2.3.4', '$ignore_time' => true)

      expect(@log).to eq([[:group_update, 'data' => {
        '$token' => token,
        '$time' => (@time_now.to_f * 1000).to_i,
        '$group_key' => '$user_id',
        '$group_id' => 'user_123',
        '$company_id' => 'acme',
        '$set' => {'plan' => 'pro'},
        '$ip' => '1.2.3.4',
        '$ignore_time' => true,
      }]])
    end

    it 'refuses any generic update operation outside the supported six' do
      %w[$add $append $merge $increment $foo].each do |operation|
        expect { @hg.people.update('$distinct_id' => '$company:acme|$user:user_123', operation => {'a' => 1}) }
          .to raise_error(Mixpanel::UnsupportedOperationError, /#{Regexp.escape(operation)}/)
      end
      expect { @hg.people.update('$distinct_id' => '$company:acme|$user:user_123', :$foo => {'a' => 1}) }
        .to raise_error(Mixpanel::UnsupportedOperationError, /\$foo/)
      expect(@log).to be_empty
    end

    it 'allows non-operation keys in a generic update' do
      @hg.people.update('$distinct_id' => '$company:acme|$user:user_123', '$set' => {'plan' => 'pro'},
                        '$token' => token, '$time' => 1, '$ip' => '1.2.3.4', '$ignore_time' => true,
                        '$mp_metadata' => {}, '$company_id' => 'acme',
                        '$group_key' => '$user_id', '$group_id' => 'user_123', 'custom' => 1)

      expect(last_type).to eq(:group_update)
      expect(last_data['$set']).to eq('plan' => 'pro')
    end

    it 'sends any generic update operation unchanged on a legacy tracker' do
      @legacy.people.update('$distinct_id' => 'user_123', '$foo' => {'a' => 1})
      expect(last_type).to eq(:profile_update)
      expect(last_data['$foo']).to eq('a' => 1)
    end

    it 'refuses a generic update without a $distinct_id on a hierarchical tracker' do
      expect { @hg.people.update('$set' => {'plan' => 'pro'}) }.to raise_error(Mixpanel::InvalidIdentityError)
      expect(@log).to be_empty
    end

    it 'sends people updates unchanged on a legacy tracker' do
      @legacy.people.set('user_123', {'plan' => 'pro'})

      expect(last_type).to eq(:profile_update)
      expect(last_data['$distinct_id']).to eq('user_123')
    end

    it 'reroutes an identity set to the user group profile' do
      @hg.people.set(user_in_acme, {'role' => 'admin'})

      expect(@log).to eq([[:group_update, 'data' => {
        '$token' => token,
        '$time' => (@time_now.to_f * 1000).to_i,
        '$group_key' => '$user_id',
        '$group_id' => 'user_123',
        '$set' => {'role' => 'admin'},
        '$company_id' => 'acme',
      }]])
    end

    it 'reroutes every identity profile operation' do
      @hg.people.set(user_in_acme, {'plan' => 'pro'})
      @hg.people.set_once(user_in_acme, {'plan' => 'pro'})
      @hg.people.delete_user(user_in_acme)
      @hg.people.union(user_in_acme, {'tags' => ['a']})
      @hg.people.unset(user_in_acme, 'plan')

      %w[$set $set_once $delete $union $unset].zip(@log).each do |operation, (type, message)|
        expect(type).to eq(:group_update)
        expect(message['data']).to have_key(operation)
        expect(message['data']['$company_id']).to eq('acme')
        expect(message['data']['$group_id']).to eq('user_123')
        expect(message['data']).not_to have_key('$distinct_id')
      end
      expect(@log.length).to eq(5)
    end

    it 'requires a hierarchical tracker for a hierarchical identity' do
      expect { @legacy.people.set(user_in_acme, {'role' => 'admin'}) }.to raise_error(Mixpanel::InvalidIdentityError)
    end

    it 'accepts a user from the bound company' do
      @hg.for_company('acme').people.set(user_in_acme, {'role' => 'admin'})

      expect(last_data['$company_id']).to eq('acme')
    end

    it 'refuses a user from another company on a bound tracker' do
      bound = @hg.for_company('other')

      expect { bound.people.set(user_in_acme, {'role' => 'admin'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, /bound to company "other".*belongs to company "acme"/)
      expect { bound.people.set('$company:acme|$user:user_123', {'role' => 'admin'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, /belongs to company "acme"/)
      expect(@log).to be_empty
    end

    it 'keeps the bound company when the caller changes its string afterwards' do
      company_id = +'acme'
      bound = @hg.for_company(company_id)
      company_id.replace('other')

      bound.company.set({'tier' => 'pro'})
      expect(last_data['$group_id']).to eq('acme')
      bound.people.set(user_in_acme, {'role' => 'admin'})
      expect(last_data['$company_id']).to eq('acme')
    end

    it 'compares the bound company and the user company as strings' do
      @hg.for_company(7).people.set(identity(user_id: 'user_123', company_id: '7'), {'role' => 'admin'})
      expect(last_data['$company_id']).to eq('7')
      @hg.for_company(7).people.set('$company:7|$user:user_123', {'role' => 'admin'})
      expect(last_data['$company_id']).to eq('7')
      @hg.for_company('7').people.set(identity(user_id: 1, company_id: 7), {'role' => 'admin'})
      expect(last_data['$company_id']).to eq('7')
      expect(last_data['$group_id']).to eq('1')
      expect { @hg.for_company(8).people.set(identity(user_id: 1, company_id: 7), {'role' => 'admin'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, /bound to company 8/)
    end

    it 'leaves the unbound tracker people unchanged' do
      @hg.for_company('other')
      @hg.people.set(user_in_acme, {'role' => 'admin'})

      expect(last_data['$company_id']).to eq('acme')
    end

    it 'lets the identity company win over a $company_id param' do
      @hg.people.set(user_in_acme, {'role' => 'admin'}, nil, {'$company_id' => 'other'})

      expect(last_data['$company_id']).to eq('acme')
    end

    it 'takes the company from a $company_id param for a user with a device' do
      @hg.people.set(identity(user_id: 'user_123', device_id: 'd'), {'role' => 'admin'}, nil, {'$company_id' => 'acme'})

      expect(last_type).to eq(:group_update)
      expect(last_data['$company_id']).to eq('acme')
    end

    it 'requires a company for a user with a device and no $company_id param' do
      expect { @hg.people.set(identity(user_id: 'user_123', device_id: 'd'), {'role' => 'admin'}) }
        .to raise_error(Mixpanel::CompanyRequiredError)
    end

    it 'takes the company from a bound tracker for a user without one' do
      @hg.for_company('acme').people.set(identity(user_id: 'user_123'), {'role' => 'admin'})

      expect(last_type).to eq(:group_update)
      expect(last_data['$group_id']).to eq('user_123')
      expect(last_data['$company_id']).to eq('acme')
    end

    it 'lets the bound company win over a $company_id param' do
      @hg.for_company('acme').people.set(identity(user_id: 'user_123'), {'role' => 'admin'}, nil, {'$company_id' => 'other'})

      expect(last_data['$company_id']).to eq('acme')
    end

    it 'does not count an empty $company_id param as a company' do
      expect { @hg.people.set(identity(user_id: 'user_123'), {'role' => 'admin'}, nil, {'$company_id' => ''}) }
        .to raise_error(Mixpanel::CompanyRequiredError)
      expect(@log).to be_empty
    end

    it 'refuses a $company_id param that is not a String or an Integer, or is only whitespace' do
      [{'x' => 1}, true, 1.5, ['acme'], '  ', ' '].each do |company_id|
        expect { @hg.people.set(identity(user_id: 'user_123'), {'role' => 'admin'}, nil, {'$company_id' => company_id}) }
          .to raise_error(Mixpanel::InvalidIdentityError, /\$company_id/)
      end
      expect(@log).to be_empty
    end

    it 'sends a valid $company_id param as a string' do
      @hg.people.set(identity(user_id: 'user_123'), {'role' => 'admin'}, nil, {'$company_id' => 7})
      expect(last_data).to include('$group_id' => 'user_123', '$company_id' => '7')
    end

    it 'sends Integer identity ids as strings' do
      @hg.people.set(identity(user_id: 3190316, company_id: 3190317), {'role' => 'admin'})
      expect(last_data).to include('$group_key' => '$user_id', '$group_id' => '3190316', '$company_id' => '3190317')
    end

    it 'refuses a combined distinct id whose $company_id param differs' do
      combined = '$company:c6|$user:u6'
      expect { @hg.people.set(combined, {'role' => 'admin'}, nil, {'$company_id' => 'zz6'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, 'distinct_id $company:c6|$user:u6 names company c6, but $company_id is zz6. Nothing sent')
      expect { @hg.people.update('$distinct_id' => combined, '$set' => {'role' => 'admin'}, '$company_id' => 'zz6') }
        .to raise_error(Mixpanel::InvalidIdentityError, /names company c6, but \$company_id is zz6/)
      expect { @hg.people.set(identity(distinct_id: combined), {'role' => 'admin'}, nil, {'$company_id' => 'zz6'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, /names company c6/)
      expect(@log).to be_empty
    end

    it 'sends a combined distinct id with a matching $company_id param' do
      @hg.people.set('$company:7|$user:u6', {'role' => 'admin'}, nil, {'$company_id' => 7})
      expect(last_data).to include('$group_id' => 'u6', '$company_id' => '7')
      @hg.people.update('$distinct_id' => '$company:c6|$user:u6', '$set' => {'role' => 'admin'}, '$company_id' => 'c6')
      expect(last_data).to include('$group_id' => 'u6', '$company_id' => 'c6')
    end

    it 'refuses a combined distinct id with a blank company or user' do
      {
        '$company:|$user:u' => 'company', '$company: |$user:u' => 'company', '$company:|$user:' => 'company',
        '$company: |$user:' => 'company', '$company:c|$user:' => 'user', '$company:c|$user:  ' => 'user'
      }.each do |distinct_id, part|
        message = "distinct_id #{distinct_id.inspect} names a blank #{part}. Nothing sent"
        expect { @hg.people.set(distinct_id, {'role' => 'admin'}) }.to raise_error(Mixpanel::InvalidIdentityError, message)
        expect { @hg.people.set(identity(distinct_id: distinct_id), {'role' => 'admin'}) }
          .to raise_error(Mixpanel::InvalidIdentityError, message)
        expect { @hg.people.update('$distinct_id' => distinct_id, '$set' => {'a' => 1}) }
          .to raise_error(Mixpanel::InvalidIdentityError, message)
      end
      expect(@log).to be_empty
    end

    it 'refuses an identity whose combined distinct id names a different user or company' do
      conflicting = identity(distinct_id: '$company:acme|$user:old', user_id: 'new', company_id: 'acme')
      user_message = 'distinct_id $company:acme|$user:old names user old, but user_id is new. Nothing sent'
      expect { @hg.people.set(conflicting, {'role' => 'admin'}) }.to raise_error(Mixpanel::InvalidIdentityError, user_message)
      expect { @hg.people.set_once(conflicting, {'role' => 'admin'}) }.to raise_error(Mixpanel::InvalidIdentityError, user_message)
      expect { @hg.people.unset(conflicting, ['role']) }.to raise_error(Mixpanel::InvalidIdentityError, user_message)
      expect { @hg.people.union(conflicting, {'tags' => ['a']}) }.to raise_error(Mixpanel::InvalidIdentityError, user_message)
      expect { @hg.people.delete_user(conflicting) }.to raise_error(Mixpanel::InvalidIdentityError, user_message)

      company_conflict = identity(distinct_id: '$company:acme|$user:u', user_id: 'u', company_id: 'other')
      expect { @hg.people.set(company_conflict, {'role' => 'admin'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, 'distinct_id $company:acme|$user:u names company acme, ' \
                                       'but company_id is other. Nothing sent')
      expect { @hg.people.delete_user(company_conflict) }.to raise_error(Mixpanel::InvalidIdentityError, /names company acme/)
      expect(@log).to be_empty
    end

    it 'updates the profile of an identity whose combined distinct id agrees with its ids' do
      @hg.people.set(identity(distinct_id: '$company:7|$user:42', user_id: 42, company_id: 7), {'role' => 'admin'})
      expect(last_data).to include('$group_key' => '$user_id', '$group_id' => '42', '$company_id' => '7')
      @hg.people.delete_user(identity(distinct_id: '$company:acme|$user:u', user_id: 'u', company_id: 'acme'))
      expect(last_data).to include('$group_id' => 'u', '$company_id' => 'acme', '$delete' => '')
    end

    it 'sends a distinct id identity to /engage on a legacy tracker' do
      @legacy.people.set(identity(distinct_id: 'user_123'), {'role' => 'admin'})

      expect(last_type).to eq(:profile_update)
      expect(last_data['$distinct_id']).to eq('user_123')
    end

    it 'sends a combined distinct id identity to the user group profile on a hierarchical tracker' do
      @hg.people.set(identity(distinct_id: '$company:acme|$user:user_123'), {'role' => 'admin'})

      expect(last_type).to eq(:group_update)
      expect(last_data).not_to have_key('$distinct_id')
      expect(last_data['$group_id']).to eq('user_123')
      expect(last_data['$company_id']).to eq('acme')
    end

    it 'rejects a device identity on both kinds of tracker' do
      device = identity(device_id: 'device_abc')

      expect { @hg.people.set(device, {'plan' => 'pro'}) }.to raise_error(Mixpanel::InvalidIdentityError, /names no user/)
      expect { @legacy.people.set(device, {'plan' => 'pro'}) }.to raise_error(Mixpanel::InvalidIdentityError, /cannot identify a profile/)
    end

    it 'rejects a company-only identity and points at the company profile' do
      expect { @hg.people.set(identity(company_id: 'acme'), {'tier' => 'ent'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, /for_company\(company_id\)\.company\.set/)
    end

    it 'keeps $add and $append refused on a company-bound tracker' do
      expect { @hg.for_company('acme').people.increment('user_123', {'logins' => 1}) }
        .to raise_error(Mixpanel::UnsupportedOperationError)
    end
  end

  describe 'group profiles' do
    it 'adds a top-level $company_id when bound to a company' do
      @hg.for_company('acme').groups.set('department', 'finance', {'plan' => 'enterprise'})

      expect(last_data['$company_id']).to eq('acme')
      expect(last_data['$group_key']).to eq('department')
      expect(last_data['$group_id']).to eq('finance')
      expect(last_data['$set']).not_to have_key('$company_id')
    end

    it 'gives user and company profiles bare group ids' do
      acme = @hg.for_company('acme')

      acme.groups.set('$user_id', 'user_123', {'role' => 'admin'})
      expect(last_data).to include('$group_key' => '$user_id', '$group_id' => 'user_123', '$company_id' => 'acme')

      acme.groups.set('$company_id', 'acme', {'tier' => 'ent'})
      expect(last_data).to include('$group_key' => '$company_id', '$group_id' => 'acme', '$company_id' => 'acme')
    end

    it 'adds the company to every group operation' do
      groups = @hg.for_company('acme').groups
      groups.set('department', 'finance', {'plan' => 'enterprise'})
      groups.set_once('department', 'finance', {'plan' => 'enterprise'})
      groups.delete_group('department', 'finance')
      groups.remove('department', 'finance', {'plan' => 'enterprise'})
      groups.union('department', 'finance', {'tags' => ['a']})
      groups.unset('department', 'finance', 'plan')

      expect(@log.length).to eq(6)
      @log.each { |_, message| expect(message['data']['$company_id']).to eq('acme') }
    end

    it 'requires a company on a hierarchical tracker' do
      expect { @hg.groups.set('department', 'finance', {'plan' => 'enterprise'}) }
        .to raise_error(Mixpanel::CompanyRequiredError, /for_company/)
      expect(@log).to be_empty
    end

    it 'accepts a $company_id param' do
      @hg.groups.set('department', 'finance', {'plan' => 'x'}, nil, {'$company_id' => 'acme'})

      expect(last_data['$company_id']).to eq('acme')
    end

    it 'does not count an empty $company_id param as a company' do
      expect { @hg.groups.set('department', 'finance', {'plan' => 'x'}, nil, {'$company_id' => ''}) }
        .to raise_error(Mixpanel::CompanyRequiredError)
      expect(@log).to be_empty
    end

    it 'refuses a $company_id param that is not a String or an Integer, or is only whitespace' do
      [{'x' => 1}, true, false, 1.5, ['acme'], :acme, '  ', " \t"].each do |company_id|
        expect { @hg.groups.set('department', 'finance', {'plan' => 'x'}, nil, {'$company_id' => company_id}) }
          .to raise_error(Mixpanel::InvalidIdentityError, /\$company_id/)
      end
      expect { @hg.groups.update('$group_key' => 'department', '$group_id' => 'f', '$set' => {}, '$company_id' => {'x' => 1}) }
        .to raise_error(Mixpanel::InvalidIdentityError)
      expect(@log).to be_empty
    end

    it 'sends a valid $company_id param as a string' do
      @hg.groups.set('department', 'finance', {'plan' => 'x'}, nil, {'$company_id' => 7})
      expect(last_data['$company_id']).to eq('7')
      @hg.groups.set('department', 'finance', {'plan' => 'x'}, nil, {'$company_id' => ' acme '})
      expect(last_data['$company_id']).to eq(' acme ')
    end

    it 'sends any $company_id param unchanged without hierarchical groups' do
      @legacy.groups.set('department', 'finance', {'plan' => 'x'}, nil, {'$company_id' => {'x' => 1}})
      expect(last_data['$company_id']).to eq('x' => 1)
      @legacy.groups.set('department', 'finance', {'plan' => 'x'}, nil, {'$company_id' => '  '})
      expect(last_data['$company_id']).to eq('  ')
    end

    it 'lets for_company win over a $company_id param' do
      @hg.for_company('acme').groups.set('department', 'finance', {'plan' => 'x'}, nil, {'$company_id' => 'other'})

      expect(last_data['$company_id']).to eq('acme')
    end

    it 'leaves legacy groups unchanged' do
      @legacy.groups.set('company', 'Acme Inc.', {'plan' => 'x'})

      expect(last_data).not_to have_key('$company_id')
      expect(last_data['$group_key']).to eq('company')
    end

    it 'raises for an unsupported group operation' do
      groups = @hg.for_company('acme').groups

      %w[$add $append $merge].each do |operation|
        expect { groups.update('$group_key' => 'company', '$group_id' => 'acme', operation => {'seats' => 1}) }
          .to raise_error(Mixpanel::UnsupportedOperationError, /#{Regexp.escape(operation)}/)
      end
      expect(@log).to be_empty
    end

    it 'raises for any group operation outside the supported six' do
      groups = @hg.for_company('acme').groups

      %w[$increment $foo].each do |operation|
        expect { groups.update('$group_key' => 'company', '$group_id' => 'acme', operation => {'seats' => 1}) }
          .to raise_error(Mixpanel::UnsupportedOperationError, /#{Regexp.escape(operation)}/)
      end
      expect(@log).to be_empty
    end

    it 'allows non-operation keys in a group update' do
      @hg.for_company('acme').groups.update('$group_key' => 'company', '$group_id' => 'acme',
                                            '$set' => {'seats' => 1}, '$token' => token, '$time' => 1,
                                            '$ip' => '1.2.3.4', '$ignore_time' => true,
                                            '$mp_metadata' => {}, '$company_id' => 'acme')
      expect(last_type).to eq(:group_update)
      expect(last_data['$set']).to eq('seats' => 1)
    end

    it 'refuses $ignore_alias and $distinct_id on a group or company update' do
      acme = @hg.for_company('acme')
      [{'$ignore_alias' => true}, {:$ignore_alias => false}].each do |params|
        expect { acme.groups.set('department', 'finance', {'a' => 1}, nil, params) }
          .to raise_error(Mixpanel::UnsupportedOperationError, /\$ignore_alias/)
        expect { acme.company.set({'a' => 1}, nil, params) }.to raise_error(Mixpanel::UnsupportedOperationError, /\$ignore_alias/)
        expect { @hg.groups.delete_group('department', 'finance', params.merge('$company_id' => 'acme')) }
          .to raise_error(Mixpanel::UnsupportedOperationError, /\$ignore_alias/)
      end
      [{'$distinct_id' => 'x'}, {:$distinct_id => 'x'}].each do |params|
        expect { acme.groups.set('department', 'finance', {'a' => 1}, nil, params) }
          .to raise_error(Mixpanel::UnsupportedOperationError, /\$distinct_id/)
        expect { acme.company.delete(params) }.to raise_error(Mixpanel::UnsupportedOperationError, /\$distinct_id/)
      end
      expect { acme.groups.update('$group_key' => 'department', '$group_id' => 'finance', '$set' => {'a' => 1},
                                  '$distinct_id' => 'x') }
        .to raise_error(Mixpanel::UnsupportedOperationError, /\$distinct_id/)
    end

    it 'sends $ignore_alias and $distinct_id on a group update without hierarchical groups' do
      @legacy.groups.set('department', 'finance', {'a' => 1}, nil, {'$ignore_alias' => true, '$distinct_id' => 'x'})
      expect(last_data).to include('$ignore_alias' => true, '$distinct_id' => 'x')
    end

    it 'refuses a $company_id param containing a |' do
      expect { @hg.groups.set('department', 'finance', {'a' => 1}, nil, {'$company_id' => 'a|b'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, /must not contain '\|'/)
      expect(@log).to be_empty
      @legacy.groups.set('department', 'finance', {'a' => 1}, nil, {'$company_id' => 'a|b'})
      expect(last_data['$company_id']).to eq('a|b')
    end

    it 'raises for an unsupported group operation before checking the company' do
      expect { @hg.groups.update('$group_key' => 'company', '$group_id' => 'acme', '$add' => {'seats' => 1}) }
        .to raise_error(Mixpanel::UnsupportedOperationError)
    end

    it 'sends an unsupported group operation without hierarchical groups' do
      @legacy.groups.update('$group_key' => 'company', '$group_id' => 'acme', '$add' => {'seats' => 1})
      expect(last_type).to eq(:group_update)
      expect(last_data['$add']).to eq('seats' => 1)
    end

    it 'sends the supported group operations' do
      groups = @hg.for_company('acme').groups

      groups.set('department', 'finance', {'seats' => 1})
      groups.set_once('department', 'finance', {'seats' => 1})
      groups.unset('department', 'finance', 'seats')
      groups.union('department', 'finance', {'tags' => ['a']})
      groups.remove('department', 'finance', {'seats' => 1})
      groups.delete_group('department', 'finance')
      expect(@log.length).to eq(6)
    end

    it 'refuses a company group whose id differs from the bound company' do
      groups = @hg.for_company('acme').groups

      expect { groups.set('$company_id', 'globex', {'plan' => 'pro'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, /\$company_id=globex does not match company acme.*for_company\(globex\)\.company/)
      expect { groups.set_once('$company_id', 'globex', {'plan' => 'pro'}) }.to raise_error(Mixpanel::InvalidIdentityError)
      expect { groups.unset('$company_id', 'globex', 'plan') }.to raise_error(Mixpanel::InvalidIdentityError)
      expect { groups.union('$company_id', 'globex', {'tags' => ['a']}) }.to raise_error(Mixpanel::InvalidIdentityError)
      expect { groups.remove('$company_id', 'globex', {'tags' => 'a'}) }.to raise_error(Mixpanel::InvalidIdentityError)
      expect { groups.delete_group('$company_id', 'globex') }.to raise_error(Mixpanel::InvalidIdentityError)
      expect(@log).to be_empty
    end

    it 'refuses a company group whose id differs from the $company_id param' do
      expect { @hg.groups.set('$company_id', 'globex', {'plan' => 'pro'}, nil, {'$company_id' => 'acme'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, /\$company_id=globex does not match company acme/)
      expect(@log).to be_empty
    end

    it 'refuses a generic company group update whose id differs from its company' do
      expect { @hg.for_company('acme').groups.update('$group_key' => '$company_id', '$group_id' => 'globex',
                                                     '$set' => {'plan' => 'pro'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, /\$company_id=globex does not match company acme/)
      expect { @hg.groups.update('$group_key' => '$company_id', '$group_id' => 'globex',
                                 '$set' => {'plan' => 'pro'}, '$company_id' => 'acme') }
        .to raise_error(Mixpanel::InvalidIdentityError, /\$company_id=globex does not match company acme/)
      expect(@log).to be_empty
    end

    it 'sends a company group whose id matches the bound company' do
      @hg.for_company('acme').groups.set('$company_id', 'acme', {'plan' => 'pro'})

      expect(last_data).to eq('$token' => token, '$time' => (@time_now.to_f * 1000).to_i,
                              '$group_key' => '$company_id', '$group_id' => 'acme',
                              '$set' => {'plan' => 'pro'}, '$company_id' => 'acme')
    end

    it 'compares a company group id and its company as strings' do
      @hg.for_company(7).groups.set('$company_id', '7', {'plan' => 'pro'})
      expect(last_data).to include('$group_id' => '7', '$company_id' => '7')

      @hg.for_company('7').groups.set('$company_id', 7, {'plan' => 'pro'})
      expect(last_data).to include('$group_id' => 7, '$company_id' => '7')
    end

    it 'sends a mismatched company group unchanged without hierarchical groups' do
      @legacy.for_company('acme').groups.set('$company_id', 'globex', {'plan' => 'pro'})

      expect(last_data).to include('$group_key' => '$company_id', '$group_id' => 'globex', '$company_id' => 'acme')
    end
  end

  describe 'for_company' do
    it 'rejects an empty company' do
      expect { @hg.for_company('') }.to raise_error(Mixpanel::InvalidIdentityError)
      expect { @hg.for_company(nil) }.to raise_error(Mixpanel::InvalidIdentityError)
    end

    it 'rejects a company of only whitespace on both kinds of tracker' do
      ['  ', ' ', "\t"].each do |company_id|
        expect { @hg.for_company(company_id) }.to raise_error(Mixpanel::InvalidIdentityError, /company_id/)
        expect { @legacy.for_company(company_id) }.to raise_error(Mixpanel::InvalidIdentityError, /company_id/)
      end
    end

    it 'rejects a company containing a | on a hierarchical groups tracker only' do
      expect { @hg.for_company('a|b') }.to raise_error(Mixpanel::InvalidIdentityError, /must not contain '\|'/)
      expect { @legacy.for_company('a|b') }.not_to raise_error
    end

    it 'sends an Integer bound company as a string' do
      @hg.for_company(3190317).groups.set('department', 'finance', {'plan' => 'x'})
      expect(last_data['$company_id']).to eq('3190317')
    end

    it 'accepts Integer companies, including 0' do
      [0, 7].each do |company_id|
        @hg.for_company(company_id).company.set({'tier' => 'pro'})
        expect(last_data['$company_id']).to eq(company_id.to_s)
        expect(last_data['$group_id']).to eq(company_id.to_s)
      end
    end

    it 'rejects companies that are not a String or an Integer' do
      [true, false, 1.5, ['acme'], {'id' => 'acme'}, :acme].each do |company_id|
        expect { @hg.for_company(company_id) }.to raise_error(Mixpanel::InvalidIdentityError, /company_id/)
      end
    end

    it 'returns a new tracker and leaves the receiver unchanged' do
      acme = @hg.for_company('acme')

      expect(acme).to be_a(Mixpanel::Tracker)
      expect(acme).not_to equal(@hg)
      expect(acme.company_id).to eq('acme')
      expect(@hg.company_id).to be_nil
      expect { @hg.groups.set('department', 'finance', {}) }.to raise_error(Mixpanel::CompanyRequiredError)
    end

    it 'shares the consumer, error handler and flag providers' do
      sent = []
      handler = Mixpanel::ErrorHandler.new
      tracker = Mixpanel::Tracker.new(token, handler, hierarchical_groups: true,
                                      local_flags_config: {}, remote_flags_config: {}) do |type, message|
        sent << type
        raise Mixpanel::ConnectionError, 'down' if type == :group_update
      end
      acme = tracker.for_company('acme')

      expect(acme.local_flags).to equal(tracker.local_flags)
      expect(acme.remote_flags).to equal(tracker.remote_flags)

      expect(handler).to receive(:handle).with(instance_of(Mixpanel::ConnectionError))
      acme.track(user_in_acme, 'Signup')
      expect(acme.groups.set('department', 'finance', {})).to be false
      expect(sent).to eq([:event, :group_update])
    end

    it 'sends an Integer bound company as a string on legacy and hierarchical groups trackers' do
      @legacy.for_company(42).groups.set('department', 'finance', {'plan' => 'x'})
      expect(last_data['$company_id']).to eql('42')
      @legacy.for_company(42).company.set({'tier' => 'pro'})
      expect(last_data).to include('$group_key' => '$company_id')
      expect(last_data['$group_id']).to eql('42')
      expect(last_data['$company_id']).to eql('42')

      @hg.for_company(42).groups.set('department', 'finance', {'plan' => 'x'})
      expect(last_data['$company_id']).to eql('42')
      @hg.for_company(42).company.set({'tier' => 'pro'})
      expect(last_data['$group_id']).to eql('42')
      expect(last_data['$company_id']).to eql('42')
    end

    it 'works on a legacy tracker' do
      @legacy.for_company('acme').groups.set('company', 'acme', {'plan' => 'x'})

      expect(last_data['$company_id']).to eq('acme')
    end
  end

  describe 'company profile' do
    def company_and_group_calls
      [
        [->(c) { c.set({'tier' => 'enterprise'}) },
         ->(g) { g.set('$company_id', 'acme', {'tier' => 'enterprise'}) }],
        [->(c) { c.set({'tier' => 'enterprise'}, '1.2.3.4', {'$ignore_time' => true}) },
         ->(g) { g.set('$company_id', 'acme', {'tier' => 'enterprise'}, '1.2.3.4', {'$ignore_time' => true}) }],
        [->(c) { c.set_once({'First Seen' => DateTime.new(2024, 1, 2, 3, 4, 5)}) },
         ->(g) { g.set_once('$company_id', 'acme', {'First Seen' => DateTime.new(2024, 1, 2, 3, 4, 5)}) }],
        [->(c) { c.remove({'Products' => 'legacy'}) },
         ->(g) { g.remove('$company_id', 'acme', {'Products' => 'legacy'}) }],
        [->(c) { c.union({'Products' => ['analytics']}) },
         ->(g) { g.union('$company_id', 'acme', {'Products' => ['analytics']}) }],
        [->(c) { c.unset('Overdue Since') },
         ->(g) { g.unset('$company_id', 'acme', 'Overdue Since') }],
        [->(c) { c.unset(['Overdue Since', 'Paid Date'], nil, {'$ignore_time' => true}) },
         ->(g) { g.unset('$company_id', 'acme', ['Overdue Since', 'Paid Date'], nil, {'$ignore_time' => true}) }],
        [->(c) { c.delete },
         ->(g) { g.delete_group('$company_id', 'acme') }],
        [->(c) { c.delete({'$ignore_time' => true}) },
         ->(g) { g.delete_group('$company_id', 'acme', {'$ignore_time' => true}) }],
      ]
    end

    [true, false].each do |hierarchical_groups|
      it "sends exactly what the matching group call sends (hierarchical_groups: #{hierarchical_groups})" do
        sent = []
        tracker = Mixpanel::Tracker.new(token, hierarchical_groups: hierarchical_groups) do |type, message|
          sent << [type, message]
        end
        acme = tracker.for_company('acme')

        company_and_group_calls.each do |company_call, group_call|
          sent.clear
          expect(company_call.call(acme.company)).to be true
          group_call.call(acme.groups)

          expect(sent.length).to eq(2)
          expect(sent[0]).to eq(sent[1])
          expect(sent[0][0]).to eq(:group_update)
        end
      end

      it "raises without a bound company (hierarchical_groups: #{hierarchical_groups})" do
        tracker = hierarchical_groups ? @hg : @legacy

        company_and_group_calls.each do |company_call, _|
          expect { company_call.call(tracker.company) }
            .to raise_error(Mixpanel::CompanyRequiredError, /for_company/)
        end
        expect(@log).to be_empty
      end
    end

    it 'leaves the receiver of for_company unbound' do
      acme = @hg.for_company('acme')
      acme.company.set({'tier' => 'enterprise'})

      expect(last_data).to include('$group_key' => '$company_id', '$group_id' => 'acme', '$company_id' => 'acme')
      expect { @hg.company.set({'tier' => 'enterprise'}) }.to raise_error(Mixpanel::CompanyRequiredError)
    end
  end

  describe 'params that would retarget a profile update' do
    def retarget(key, value, expected)
      "#{key} #{value.inspect} does not match the message's #{key} #{expected.inspect}, " \
        'and would send the update to a different profile. Nothing sent'
    end

    it 'refuses a $group_id, $group_key or $token param naming another user profile' do
      acme = @hg.for_company('acme')
      [user_in_acme, '$company:acme|$user:user_123'].each do |user|
        expect { @hg.people.set(user, {'role' => 'admin'}, nil, {'$group_id' => 'u2'}) }
          .to raise_error(Mixpanel::InvalidIdentityError, retarget('$group_id', 'u2', 'user_123'))
        expect { @hg.people.set(user, {'role' => 'admin'}, nil, {:'$group_id' => 'u2'}) }
          .to raise_error(Mixpanel::InvalidIdentityError, retarget('$group_id', 'u2', 'user_123'))
        expect { @hg.people.unset(user, ['role'], nil, {'$group_key' => 'department'}) }
          .to raise_error(Mixpanel::InvalidIdentityError, retarget('$group_key', 'department', '$user_id'))
        expect { @hg.people.set(user, {'role' => 'admin'}, nil, {'$token' => 'OTHER'}) }
          .to raise_error(Mixpanel::InvalidIdentityError, retarget('$token', 'OTHER', token))
        expect { acme.people.set_once(user, {'role' => 'admin'}, nil, {'$group_id' => 'u2'}) }
          .to raise_error(Mixpanel::InvalidIdentityError, /\$group_id "u2"/)
      end
      # With user_id == company_id, a $group_key param would turn a user delete into a company delete.
      expect { @hg.people.delete_user(identity(user_id: 'acme', company_id: 'acme'), {'$group_key' => '$company_id'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, retarget('$group_key', '$company_id', '$user_id'))
      expect(@log).to be_empty
    end

    it 'refuses a $distinct_id param naming another profile than the identity' do
      expect { @hg.people.set(user_in_acme, {'role' => 'admin'}, nil, {'$distinct_id' => '$company:acme|$user:u2'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, /\APass either an identity or a \$distinct_id, not both/)
      combined = identity(distinct_id: '$company:acme|$user:user_123')
      expect { @hg.people.set(combined, {'role' => 'admin'}, nil, {'$distinct_id' => '$company:acme|$user:u2'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, /\APass either an identity or a \$distinct_id, not both/)
      expect(@log).to be_empty
    end

    it 'refuses a generic user update message naming another group or token' do
      base = {'$distinct_id' => '$company:acme|$user:user_123', '$set' => {'role' => 'admin'}}
      expect { @hg.people.update(base.merge('$group_id' => 'u2')) }
        .to raise_error(Mixpanel::InvalidIdentityError, retarget('$group_id', 'u2', 'user_123'))
      expect { @hg.people.update(base.merge('$group_key' => '$company_id')) }
        .to raise_error(Mixpanel::InvalidIdentityError, retarget('$group_key', '$company_id', '$user_id'))
      expect { @hg.people.update(base.merge('$token' => 'OTHER')) }
        .to raise_error(Mixpanel::InvalidIdentityError, retarget('$token', 'OTHER', token))
      expect(@log).to be_empty
    end

    it 'refuses a group or company param naming another group or token' do
      acme = @hg.for_company('acme')
      expect { acme.groups.set('dept', 'fin', {'a' => 1}, nil, {'$group_id' => 'other'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, retarget('$group_id', 'other', 'fin'))
      expect { acme.groups.set_once('dept', 'fin', {'a' => 1}, nil, {'$group_key' => 'team'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, retarget('$group_key', 'team', 'dept'))
      expect { acme.groups.remove('dept', 'fin', {'a' => 1}, nil, {'$group_id' => 'other'}) }.to raise_error(Mixpanel::InvalidIdentityError)
      expect { acme.groups.union('dept', 'fin', {'a' => [1]}, nil, {'$group_id' => 'other'}) }.to raise_error(Mixpanel::InvalidIdentityError)
      expect { acme.groups.unset('dept', 'fin', ['a'], nil, {'$group_id' => 'other'}) }.to raise_error(Mixpanel::InvalidIdentityError)
      expect { acme.groups.delete_group('dept', 'fin', {'$group_id' => 'other'}) }.to raise_error(Mixpanel::InvalidIdentityError)
      expect { acme.groups.set('dept', 'fin', {'a' => 1}, nil, {'$token' => 'OTHER'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, retarget('$token', 'OTHER', token))
      expect { acme.groups.update('$group_key' => 'dept', '$group_id' => 'fin', '$set' => {}, '$token' => 'OTHER') }
        .to raise_error(Mixpanel::InvalidIdentityError, retarget('$token', 'OTHER', token))
      expect { @hg.groups.set('dept', 'fin', {'a' => 1}, nil, {'$company_id' => 'acme', '$group_id' => 'other'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, retarget('$group_id', 'other', 'fin'))
      expect { acme.company.set({'tier' => 'pro'}, nil, {'$group_id' => 'globex'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, retarget('$group_id', 'globex', 'acme'))
      expect { acme.company.delete({'$group_key' => '$user_id'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, retarget('$group_key', '$user_id', '$company_id'))
      expect(@log).to be_empty
    end

    it 'sends params equal to the message, and ordinary params, as before' do
      acme = @hg.for_company('acme')
      matching = {'$group_key' => '$user_id', '$group_id' => 'user_123', '$token' => token,
                  '$ip' => '1.2.3.4', '$time' => 1234, '$ignore_time' => true}
      @hg.people.set(user_in_acme, {'role' => 'admin'}, nil, matching)
      expect(last_data).to include('$group_key' => '$user_id', '$group_id' => 'user_123', '$company_id' => 'acme',
                                   '$ip' => '1.2.3.4', '$time' => 1234, '$ignore_time' => true)
      @hg.people.delete_user('$company:acme|$user:user_123', matching)
      expect(last_data).to include('$group_id' => 'user_123', '$delete' => '')
      combined = identity(distinct_id: '$company:acme|$user:user_123')
      @hg.people.set(combined, {'role' => 'admin'}, nil, {'$distinct_id' => '$company:acme|$user:user_123'})
      expect(last_data).to include('$group_id' => 'user_123')
      @hg.people.update('$distinct_id' => '$company:acme|$user:user_123', '$set' => {'a' => 1},
                        '$group_key' => '$user_id', '$group_id' => 'user_123', '$token' => token)
      expect(last_data).to include('$group_id' => 'user_123', '$token' => token)
      acme.groups.set('dept', 'fin', {'a' => 1}, '1.2.3.4', {'$group_key' => 'dept', '$group_id' => 'fin', '$time' => 5})
      expect(last_data).to include('$group_key' => 'dept', '$group_id' => 'fin', '$time' => 5, '$ip' => '1.2.3.4')
      acme.company.set({'tier' => 'pro'}, nil, {'$group_id' => 'acme', '$token' => token})
      expect(last_data).to include('$group_key' => '$company_id', '$group_id' => 'acme')
    end

    it 'sends a user profile update to the profile a $distinct_id param names, without $distinct_id' do
      param = {'$distinct_id' => '$company:acme|$user:u2'}
      @hg.people.set('$company:acme|$user:user_123', {'role' => 'admin'}, nil, param)
      expect(last_type).to eq(:group_update)
      expect(last_data).to include('$group_key' => '$user_id', '$group_id' => 'u2', '$company_id' => 'acme',
                                   '$set' => {'role' => 'admin'})
      expect(last_data).not_to have_key('$distinct_id')
      # Like a distinct_id argument, the param need not agree with the argument it replaces.
      @hg.people.set_once('not combined', {'a' => 1}, nil, {:'$distinct_id' => '$company:globex|$user:u3'})
      expect(last_data).to include('$group_id' => 'u3', '$company_id' => 'globex', '$set_once' => {'a' => 1})
      expect(last_data.keys).not_to include('$distinct_id')
      @hg.people.union('$company:acme|$user:user_123', {'l' => [1]}, nil, param)
      expect(last_data).to include('$group_id' => 'u2', '$union' => {'l' => [1]})
      @hg.people.unset('$company:acme|$user:user_123', 'role', nil, param)
      expect(last_data).to include('$group_id' => 'u2', '$unset' => ['role'])
      @hg.people.delete_user('$company:acme|$user:user_123', param.merge('$company_id' => 'acme'))
      expect(last_data).to include('$group_id' => 'u2', '$company_id' => 'acme', '$delete' => '')
      @hg.for_company('acme').people.set('$company:acme|$user:user_123', {'a' => 1}, nil, param)
      expect(last_data).to include('$group_id' => 'u2', '$company_id' => 'acme')
      combined = identity(distinct_id: '$company:acme|$user:user_123')
      @hg.people.set(combined, {'a' => 1}, nil, {'$distinct_id' => '$company:acme|$user:user_123'})
      expect(last_data).to include('$group_id' => 'user_123', '$company_id' => 'acme')
      @hg.people.set(user_in_acme, {'a' => 1}, nil, {'$distinct_id' => nil})
      expect(last_data).to include('$group_id' => 'user_123', '$company_id' => 'acme')
      expect(@log.map { |_, message| message['data'].keys }.flatten).not_to include('$distinct_id')
      expect(@log.length).to eq(8)
    end

    it 'refuses a $distinct_id param naming no user profile, another company or another group' do
      expect { @hg.people.set('$company:acme|$user:user_123', {'a' => 1}, nil, {'$distinct_id' => 'user_123'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, /distinct id "user_123" does not name both/)
      expect { @hg.people.set('$company:acme|$user:user_123', {'a' => 1}, nil, {'$distinct_id' => nil}) }
        .to raise_error(Mixpanel::InvalidIdentityError, /distinct id nil does not name both/)
      expect { @hg.people.set('$company:acme|$user:user_123', {'a' => 1}, nil, {'$distinct_id' => '$company: |$user:u'}) }
        .to raise_error(Mixpanel::InvalidIdentityError, /names a blank company/)
      expect do
        @hg.people.set('$company:acme|$user:user_123', {'a' => 1}, nil,
                       {'$distinct_id' => '$company:globex|$user:u2', '$company_id' => 'acme'})
      end.to raise_error(Mixpanel::InvalidIdentityError, 'distinct_id $company:globex|$user:u2 names company globex, ' \
                                        'but $company_id is acme. Nothing sent')
      expect do
        @hg.for_company('acme').people.set('$company:acme|$user:user_123', {'a' => 1}, nil,
                                           {'$distinct_id' => '$company:globex|$user:u2'})
      end.to raise_error(Mixpanel::InvalidIdentityError, /bound to company "acme", but .*user_id=u2.* belongs to company "globex"/)
      expect do
        @hg.people.set('$company:acme|$user:user_123', {'a' => 1}, nil,
                       {'$distinct_id' => '$company:acme|$user:u2', '$group_id' => 'user_123'})
      end.to raise_error(Mixpanel::InvalidIdentityError, /\$group_id "user_123" does not match the message's \$group_id "u2"/)
      expect(@log).to be_empty
    end

    it 'sends params naming another group or token unchanged without hierarchical groups' do
      @legacy.groups.set('dept', 'fin', {'a' => 1}, nil, {'$group_id' => 'other', '$token' => 'OTHER'})
      expect(last_data).to include('$group_id' => 'other', '$token' => 'OTHER')
      @legacy.for_company('acme').company.set({'tier' => 'pro'}, nil, {'$group_id' => 'globex'})
      expect(last_data).to include('$group_id' => 'globex')
      @legacy.people.set('user_123', {'role' => 'admin'}, nil, {'$distinct_id' => 'other', '$token' => 'OTHER'})
      expect(last_data).to include('$distinct_id' => 'other', '$token' => 'OTHER')
      @legacy.people.set(identity(distinct_id: 'user_123'), {'role' => 'admin'}, nil, {'$distinct_id' => 'other'})
      expect(last_data).to include('$distinct_id' => 'other')
    end
  end

  describe 'a tracker without hierarchical groups' do
    # Every message valid in both modes is identical in both, and the legacy
    # tracker still sends the operations a hierarchical groups tracker refuses.
    def capture(hierarchical_groups)
      log = []
      tracker = Mixpanel::Tracker.new(token, credentials: @credentials, hierarchical_groups: hierarchical_groups) do |type, message|
        log << [type, message]
      end
      yield tracker
      log
    end

    it 'sends the same messages as a hierarchical groups tracker' do
      calls = proc do |tracker|
        tracker.track('user_123', 'Signup', {'plan' => 'pro'}, '1.2.3.4')
        tracker.import_events('user_123', 'Signup', {'time' => 1369353600})
        params = {'$company_id' => 'acme'}
        tracker.groups.set('company', 'acme', {'plan' => 'pro'}, nil, params)
        tracker.groups.set_once('company', 'acme', {'plan' => 'pro'}, nil, params)
        tracker.groups.union('company', 'acme', {'tags' => ['a']}, nil, params)
        tracker.groups.unset('company', 'acme', 'plan', nil, params)
        tracker.groups.remove('company', 'acme', {'tags' => 'a'}, nil, params)
        tracker.groups.delete_group('company', 'acme', params)
        tracker.for_company('acme').groups.set('company', 'acme', {'plan' => 'pro'})
      end

      legacy = capture(false, &calls)
      expect(legacy.length).to eq(9)
      expect(capture(true, &calls)).to eq(legacy)
    end

    it 'sends people updates to /engage, where a hierarchical groups tracker uses /groups' do
      id = '$company:acme|$user:user_123'
      calls = proc do |tracker|
        tracker.people.set(id, {'plan' => 'pro'}, '1.2.3.4', {'$ignore_time' => true})
        tracker.people.set_once(id, {'plan' => 'pro'})
        tracker.people.union(id, {'tags' => ['a']})
        tracker.people.unset(id, ['plan', 'tier'])
        tracker.people.delete_user(id, {'$ignore_time' => true})
        tracker.people.update('$distinct_id' => id, '$set' => {'plan' => 'pro'})
      end
      without_distinct_id = proc do |log|
        log.map do |_, message|
          JSON.load(message)['data'].reject { |key, _| %w[$distinct_id $group_key $group_id $company_id].include?(key) }
        end
      end

      legacy = capture(false, &calls)
      expect(legacy.map(&:first)).to eq([:profile_update] * 6)
      legacy.each { |_, message| expect(JSON.load(message)['data']['$distinct_id']).to eq(id) }

      hierarchical = capture(true, &calls)
      expect(hierarchical.map(&:first)).to eq([:group_update] * 6)
      hierarchical.each do |_, message|
        data = JSON.load(message)['data']
        expect(data['$group_key']).to eq('$user_id')
        expect(data['$group_id']).to eq('user_123')
        expect(data['$company_id']).to eq('acme')
      end
      expect(without_distinct_id.call(hierarchical)).to eq(without_distinct_id.call(legacy))
    end

    it 'sends a plain distinct id to /engage, which a hierarchical groups tracker refuses' do
      legacy = capture(false) { |tracker| tracker.people.set('user_123', {'plan' => 'pro'}) }
      expect(legacy.map(&:first)).to eq([:profile_update])
      expect(JSON.load(legacy.first[1])['data']['$distinct_id']).to eq('user_123')

      expect { capture(true) { |tracker| tracker.people.set('user_123', {'plan' => 'pro'}) } }
        .to raise_error(Mixpanel::InvalidIdentityError)
    end

    it 'still sends increment, plus_one, append, track_charge and generic updates' do
      log = capture(false) do |tracker|
        tracker.people.increment('user_123', {'logins' => 1})
        tracker.people.plus_one('user_123', 'logins')
        tracker.people.append('user_123', {'plan' => 'pro'})
        tracker.people.track_charge('user_123', 9.99)
        tracker.people.update('$distinct_id' => 'user_123', '$add' => {'logins' => 1})
        tracker.groups.set('company', 'acme', {'plan' => 'pro'})
      end

      messages = log.map { |type, message| [type, JSON.load(message)['data']] }
      expect(messages.map(&:first)).to eq([:profile_update] * 5 + [:group_update])
      expect(messages[0][1]['$add']).to eq('logins' => 1)
      expect(messages[1][1]['$add']).to eq('logins' => 1)
      expect(messages[2][1]['$append']).to eq('plan' => 'pro')
      expect(messages[3][1]['$append']).to eq('$transactions' => {'$amount' => 9.99})
      expect(messages[5][1]).not_to have_key('$company_id')
    end
  end
end

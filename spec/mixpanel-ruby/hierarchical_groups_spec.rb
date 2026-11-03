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

  describe 'Mixpanel::Identity' do
    it 'rejects empty values' do
      # An empty string is a caller error; nil simply leaves the value unset.
      expect { identity(user_id: '') }.to raise_error(ArgumentError, /user_id/)
      expect { identity(company_id: '') }.to raise_error(ArgumentError, /company_id/)
      expect { identity(device_id: '') }.to raise_error(ArgumentError, /device_id/)
      expect { identity(distinct_id: '') }.to raise_error(ArgumentError, /distinct_id/)
    end

    it 'needs at least one value' do
      expect { Mixpanel::Identity.new }.to raise_error(ArgumentError)
      expect { identity(user_id: nil, company_id: nil) }.to raise_error(ArgumentError)
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

    it 'builds a flag context from a plain distinct id' do
      expect(identity(distinct_id: 'user_123').to_flag_context).to eq('distinct_id' => 'user_123')
    end
  end

  describe 'events' do
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

    it 'rejects a user without a company or device on a hierarchical tracker' do
      expect { @hg.track(identity(user_id: 'user_123'), 'Signup') }
        .to raise_error(ArgumentError, /cannot be merged/)
      expect(@log).to be_empty
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

      expect { @legacy.track(user_in_acme, 'Signup') }.to raise_error(ArgumentError, /hierarchical_groups: true/)
      expect { tracker.import_events(user_in_acme, 'Signup') }.to raise_error(ArgumentError)
      expect { @legacy.track(identity(company_id: 'acme'), 'Renewed') }.to raise_error(ArgumentError)
      expect(@log).to be_empty
    end

    it 'raises caller errors directly instead of passing them to the error handler' do
      handler = Mixpanel::ErrorHandler.new
      tracker = Mixpanel::Tracker.new(token, handler) { |*args| }
      expect(handler).not_to receive(:handle)

      expect { tracker.track(user_in_acme, 'Signup') }.to raise_error(ArgumentError)
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

      expect { @legacy.people.increment(id, {'logins' => 1}) }.to raise_error(ArgumentError, /increment/)
      expect { @legacy.people.append(id, {'plan' => 'pro'}) }.to raise_error(ArgumentError, /append/)
      expect { @legacy.people.track_charge(id, 9.99) }.to raise_error(ArgumentError)
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
      @hg.people.set('$company:a:b|$user:c|$user:d', {'plan' => 'pro'})

      expect(last_data['$company_id']).to eq('a:b')
      expect(last_data['$group_id']).to eq('c|$user:d')
    end

    it 'refuses a distinct id that is not a combined one on a hierarchical tracker' do
      [
        'user_123',
        '$company:acme|$user:',
        '$company:acme',
        '$company:|$user:user_123',
        '|$user:user_123',
        '$group:acme|$user:user_123',
        'company:acme|$user:user_123',
        '$user:user_123|$company:acme',
      ].each do |id|
        expect { @hg.people.set(id, {'plan' => 'pro'}) }.to raise_error(ArgumentError, /user and a company/)
        expect { @hg.people.unset(id, 'plan') }.to raise_error(ArgumentError, /\$company:\{company\}\|\$user:\{user\}/)
        expect { @hg.people.delete_user(id) }.to raise_error(ArgumentError, /Mixpanel::Identity/)
        expect { @hg.people.set(identity(distinct_id: id), {'plan' => 'pro'}) }.to raise_error(ArgumentError)
        expect { @hg.people.update('$distinct_id' => id, '$set' => {'plan' => 'pro'}) }.to raise_error(ArgumentError)
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

    it 'refuses a generic update without a $distinct_id on a hierarchical tracker' do
      expect { @hg.people.update('$set' => {'plan' => 'pro'}) }.to raise_error(ArgumentError)
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
      expect { @legacy.people.set(user_in_acme, {'role' => 'admin'}) }.to raise_error(ArgumentError)
    end

    it 'accepts a user from the bound company' do
      @hg.for_company('acme').people.set(user_in_acme, {'role' => 'admin'})

      expect(last_data['$company_id']).to eq('acme')
    end

    it 'refuses a user from another company on a bound tracker' do
      bound = @hg.for_company('other')

      expect { bound.people.set(user_in_acme, {'role' => 'admin'}) }
        .to raise_error(ArgumentError, /bound to company "other".*belongs to company "acme"/)
      expect { bound.people.set('$company:acme|$user:user_123', {'role' => 'admin'}) }
        .to raise_error(ArgumentError, /belongs to company "acme"/)
      expect(@log).to be_empty
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

      expect { @hg.people.set(device, {'plan' => 'pro'}) }.to raise_error(ArgumentError, /names no user/)
      expect { @legacy.people.set(device, {'plan' => 'pro'}) }.to raise_error(ArgumentError, /cannot identify a profile/)
    end

    it 'rejects a company-only identity and points at the company profile' do
      expect { @hg.people.set(identity(company_id: 'acme'), {'tier' => 'ent'}) }
        .to raise_error(ArgumentError, /for_company\(company_id\)\.company\.set/)
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
  end

  describe 'for_company' do
    it 'rejects an empty company' do
      expect { @hg.for_company('') }.to raise_error(ArgumentError)
      expect { @hg.for_company(nil) }.to raise_error(ArgumentError)
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
        [->(c) { c.delete({'$ignore_alias' => true}) },
         ->(g) { g.delete_group('$company_id', 'acme', {'$ignore_alias' => true}) }],
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
        tracker.people.delete_user(id, {'$ignore_alias' => true})
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
        .to raise_error(ArgumentError)
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

require 'spec_helper'
require 'base64'
require 'mixpanel-ruby'

describe 'Hierarchical groups scenarios' do
  let(:token) { 'TEST TOKEN' }

  let(:user_id) { 'my_user_id' }
  let(:company_id) { 'my_company_id' }
  let(:team_id) { 'my_team_id' }
  let(:device_id) { 'my_device_id' }
  let(:combined_distinct_id) { "$company:#{company_id}|$user:#{user_id}" }

  let(:event_keys) { %w[token time mp_lib $lib_version] }
  let(:group_keys) { %w[$token $time $group_key $group_id $company_id] }

  before(:each) do
    # Keep the credentials-with-a-sink and deprecation warnings out of the output.
    allow_any_instance_of(Mixpanel::Tracker).to receive(:warn)
    allow(Time).to receive(:now).and_return(Time.parse('Jun 6 1972, 16:23:04'))

    @log = []
    sink = proc { |type, message| @log << [type, JSON.load(message)] }
    @credentials = Mixpanel::ServiceAccountCredentials.new('user', 'secret', '123')
    @hg = Mixpanel::Tracker.new(token, credentials: @credentials, hierarchical_groups: true, &sink)
    @legacy = Mixpanel::Tracker.new(token, &sink)
    @company = @hg.for_company(company_id)
  end

  def user
    Mixpanel::Identity.new(user_id: user_id, company_id: company_id)
  end

  def only_message
    expect(@log.length).to eq(1)
    @log.first
  end

  def expect_event(type, extra_keys)
    sent_type, message = only_message
    expect(sent_type).to eq(type)
    properties = message['data']['properties']
    expect(properties.keys).to match_array(event_keys + extra_keys)
    properties
  end

  def expect_group_update(group_key, group_id, operation)
    sent_type, message = only_message
    expect(sent_type).to eq(:group_update)
    data = message['data']
    expect(data.keys).to match_array(group_keys + [operation])
    expect(data['$token']).to eq(token)
    expect(data['$group_key']).to eq(group_key)
    expect(data['$group_id']).to eq(group_id)
    expect(data['$company_id']).to eq(company_id)
    data[operation]
  end

  def expect_user_update(operation)
    expect_group_update('$user_id', user_id, operation)
  end

  def expect_company_update(operation)
    expect_group_update('$company_id', company_id, operation)
  end

  def expect_custom_group_update(operation)
    expect_group_update('team_id', team_id, operation)
  end

  def expect_nothing_sent
    expect(@log).to be_empty
  end

  # Events

  it 'Track Anonymous' do
    @hg.track(Mixpanel::Identity.new(device_id: device_id), 'Viewed')

    properties = expect_event(:event, %w[$device_id])
    expect(properties['$device_id']).to eq(device_id)
  end

  it 'Track Identified' do
    @hg.track(Mixpanel::Identity.new(user_id: user_id, company_id: company_id, device_id: device_id), 'Signup')

    properties = expect_event(:event, %w[$user_id $company_id $device_id])
    expect(properties['$user_id']).to eq(user_id)
    expect(properties['$company_id']).to eq(company_id)
    expect(properties['$device_id']).to eq(device_id)
  end

  it 'Track Identified Without Device' do
    @hg.track(user, 'Signup')

    properties = expect_event(:event, %w[$user_id $company_id])
    expect(properties['$user_id']).to eq(user_id)
    expect(properties['$company_id']).to eq(company_id)
  end

  it 'Track With Custom Group' do
    @hg.track(user, 'Signup', {'team_id' => team_id})

    properties = expect_event(:event, %w[$user_id $company_id team_id])
    expect(properties['team_id']).to eq(team_id)
  end

  it 'Import Identified' do
    @hg.import_events(user, 'Signup', {'time' => 1369353600})

    properties = expect_event(:import, %w[$user_id $company_id])
    expect(properties['$user_id']).to eq(user_id)
    expect(properties['$company_id']).to eq(company_id)
    expect(properties['time']).to eq(1369353600)
  end

  it 'Identity Overrides Properties' do
    @hg.track(user, 'Signup', {'$user_id' => 'other_user', '$company_id' => 'other_company', 'plan' => 'pro'})

    properties = expect_event(:event, %w[$user_id $company_id plan])
    expect(properties['$user_id']).to eq(user_id)
    expect(properties['$company_id']).to eq(company_id)
    expect(properties['plan']).to eq('pro')
  end

  it 'Track With Combined Distinct ID' do
    @hg.track(combined_distinct_id, 'Signup')

    properties = expect_event(:event, %w[distinct_id])
    expect(properties['distinct_id']).to eq(combined_distinct_id)
  end

  it 'Track With Combined Distinct ID Identity' do
    @hg.track(Mixpanel::Identity.new(distinct_id: combined_distinct_id), 'Signup')

    properties = expect_event(:event, %w[distinct_id])
    expect(properties['distinct_id']).to eq(combined_distinct_id)
  end

  # User profile

  it 'Set User Property' do
    @hg.people.set(user, {'plan' => 'pro'})

    expect(expect_user_update('$set')).to eq('plan' => 'pro')
  end

  it 'Set User Property With Combined Distinct ID' do
    @hg.people.set(combined_distinct_id, {'plan' => 'pro'})

    expect(expect_user_update('$set')).to eq('plan' => 'pro')
  end

  it 'Set User Property With Distinct ID (Unsupported)' do
    expect { @hg.people.set(user_id, {'plan' => 'pro'}) }.to raise_error(ArgumentError, /user and a company/)

    expect_nothing_sent
  end

  it 'Set User Property With Combined Distinct ID Identity' do
    @hg.people.set(Mixpanel::Identity.new(distinct_id: combined_distinct_id), {'plan' => 'pro'})

    expect(expect_user_update('$set')).to eq('plan' => 'pro')
  end

  it 'Set User Properties' do
    @hg.people.set(user, {'plan' => 'pro', 'role' => 'admin'})

    expect(expect_user_update('$set')).to eq('plan' => 'pro', 'role' => 'admin')
  end

  it 'Set Once User Property' do
    @hg.people.set_once(user, {'first_seen' => 'today'})

    expect(expect_user_update('$set_once')).to eq('first_seen' => 'today')
  end

  it 'Union User Property' do
    @hg.people.union(user, {'tags' => ['a', 'b']})

    expect(expect_user_update('$union')).to eq('tags' => ['a', 'b'])
  end

  it 'Remove User Property' do
    # Mixpanel::People has no remove; the user profile is the $user_id group
    # profile within the company.
    @company.groups.remove('$user_id', user_id, {'tags' => 'a'})

    expect(expect_user_update('$remove')).to eq('tags' => 'a')
  end

  it 'Unset User Property' do
    @hg.people.unset(user, 'plan')

    expect(expect_user_update('$unset')).to eq(['plan'])
  end

  it 'Delete User' do
    @hg.people.delete_user(user)

    expect(expect_user_update('$delete')).to eq('')
  end

  it 'Clear Charges (Unsupported)' do
    expect { @hg.people.clear_charges(user) }.to raise_error(Mixpanel::UnsupportedOperationError)
    expect { @hg.people.clear_charges(user_id) }.to raise_error(Mixpanel::UnsupportedOperationError)
    expect_nothing_sent
  end

  it 'Increment User Property (Unsupported)' do
    expect { @hg.people.increment(user, {'logins' => 1}) }.to raise_error(Mixpanel::UnsupportedOperationError)
    expect { @hg.people.plus_one(user, 'logins') }.to raise_error(Mixpanel::UnsupportedOperationError)
    expect_nothing_sent
  end

  it 'Append User Property (Unsupported)' do
    expect { @hg.people.append(user, {'tags' => 'a'}) }.to raise_error(Mixpanel::UnsupportedOperationError)
    expect_nothing_sent
  end

  it 'Track Charge (Unsupported)' do
    expect { @hg.people.track_charge(user, 9.99) }.to raise_error(Mixpanel::UnsupportedOperationError)
    expect_nothing_sent
  end

  # Company

  it 'Set Company Property' do
    @company.groups.set('$company_id', company_id, {'tier' => 'enterprise'})

    expect(expect_company_update('$set')).to eq('tier' => 'enterprise')
  end

  it 'Set Company Properties' do
    @company.groups.set('$company_id', company_id, {'tier' => 'enterprise', 'seats' => 50})

    expect(expect_company_update('$set')).to eq('tier' => 'enterprise', 'seats' => 50)
  end

  it 'Set Once Company Property' do
    @company.groups.set_once('$company_id', company_id, {'founded' => 2001})

    expect(expect_company_update('$set_once')).to eq('founded' => 2001)
  end

  it 'Union Company Property' do
    @company.groups.union('$company_id', company_id, {'regions' => ['us', 'eu']})

    expect(expect_company_update('$union')).to eq('regions' => ['us', 'eu'])
  end

  it 'Remove Company Property' do
    @company.groups.remove('$company_id', company_id, {'regions' => 'eu'})

    expect(expect_company_update('$remove')).to eq('regions' => 'eu')
  end

  it 'Unset Company Property' do
    @company.groups.unset('$company_id', company_id, 'tier')

    expect(expect_company_update('$unset')).to eq(['tier'])
  end

  # Custom groups

  it "Set User's Custom Group" do
    @company.people.set(user, {'team_id' => team_id})

    expect(expect_user_update('$set')).to eq('team_id' => team_id)
  end

  it "Remove User's Custom Group" do
    @company.people.unset(user, 'team_id')

    expect(expect_user_update('$unset')).to eq(['team_id'])
  end

  it 'Set Custom Group Property' do
    @company.groups.set('team_id', team_id, {'name' => 'Platform'})

    expect(expect_custom_group_update('$set')).to eq('name' => 'Platform')
  end

  it 'Set Custom Group Properties' do
    @company.groups.set('team_id', team_id, {'name' => 'Platform', 'size' => 8})

    expect(expect_custom_group_update('$set')).to eq('name' => 'Platform', 'size' => 8)
  end

  it 'Set Once Custom Group Property' do
    @company.groups.set_once('team_id', team_id, {'created' => 'today'})

    expect(expect_custom_group_update('$set_once')).to eq('created' => 'today')
  end

  it 'Union Custom Group Property' do
    @company.groups.union('team_id', team_id, {'tools' => ['git', 'ci']})

    expect(expect_custom_group_update('$union')).to eq('tools' => ['git', 'ci'])
  end

  it 'Remove Custom Group Property' do
    @company.groups.remove('team_id', team_id, {'tools' => 'ci'})

    expect(expect_custom_group_update('$remove')).to eq('tools' => 'ci')
  end

  it 'Unset Custom Group Property' do
    @company.groups.unset('team_id', team_id, 'name')

    expect(expect_custom_group_update('$unset')).to eq(['name'])
  end

  it 'Delete Company' do
    @company.groups.delete_group('$company_id', company_id)

    expect(expect_company_update('$delete')).to eq('')
  end

  it 'Delete Custom Group' do
    @company.groups.delete_group('team_id', team_id)

    expect(expect_custom_group_update('$delete')).to eq('')
  end

  # Unsupported / rejected

  it 'Identify Without Company' do
    user_only = Mixpanel::Identity.new(user_id: user_id)

    expect { @hg.people.set(user_only, {'plan' => 'pro'}) }.to raise_error(ArgumentError, /needs a company/)
    expect { @hg.track(user_only, 'Signup') }.to raise_error(ArgumentError, /needs a company/)
    expect_nothing_sent
  end

  it 'Set User Property Without User' do
    company_only = Mixpanel::Identity.new(company_id: company_id)

    expect { @hg.people.set(company_only, {'plan' => 'pro'}) }.to raise_error(ArgumentError, /require a user id/)
    expect_nothing_sent
  end

  it 'Set Company Property Without Company' do
    expect { @hg.groups.set('$company_id', company_id, {'tier' => 'enterprise'}) }
      .to raise_error(Mixpanel::CompanyRequiredError)
    expect_nothing_sent
  end

  it 'Set Custom Group Property Without Company' do
    expect { @hg.groups.set('team_id', team_id, {'name' => 'Platform'}) }
      .to raise_error(Mixpanel::CompanyRequiredError)
    expect_nothing_sent
  end

  it 'Company Identity Without Hierarchical Groups' do
    expect { @legacy.track(user, 'Signup') }.to raise_error(ArgumentError, /hierarchical groups tracker/)
    expect { @legacy.people.set(user, {'plan' => 'pro'}) }.to raise_error(ArgumentError, /hierarchical groups tracker/)
    expect_nothing_sent
  end

  it 'Alias' do
    # A hierarchical groups user is identified by company and user id, so there is nothing to alias.
    WebMock.reset!
    expect { @hg.alias('my_alias', user_id) }
      .to raise_error(Mixpanel::UnsupportedOperationError, /alias is not supported/)
    expect(WebMock).not_to have_requested(:any, 'https://api.mixpanel.com/track')
    expect_nothing_sent
  end

  # Without hierarchical groups

  it 'Track With Distinct ID' do
    @legacy.track(user_id, 'Signup')

    properties = expect_event(:event, %w[distinct_id])
    expect(properties['distinct_id']).to eq(user_id)
  end

  it 'Set User Property With Distinct ID' do
    @legacy.people.set(user_id, {'plan' => 'pro'})

    sent_type, message = only_message
    expect(sent_type).to eq(:profile_update)
    data = message['data']
    expect(data.keys).to match_array(%w[$token $time $distinct_id $set])
    expect(data['$distinct_id']).to eq(user_id)
    expect(data['$set']).to eq('plan' => 'pro')
  end

  it 'Set Group Property' do
    @legacy.groups.set('team_id', team_id, {'name' => 'Platform'})

    sent_type, message = only_message
    expect(sent_type).to eq(:group_update)
    data = message['data']
    expect(data.keys).to match_array(%w[$token $time $group_key $group_id $set])
    expect(data['$group_key']).to eq('team_id')
    expect(data['$group_id']).to eq(team_id)
  end
end

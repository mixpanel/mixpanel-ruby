require 'json'
require 'date'

class MixpanelPeopleDate
  def initialize(date)
    @date = date
  end

  def to_json(*a)
    @date.strftime('%Y-%m-%dT%H:%M:%S').to_json(*a)
  end

  def self.asPeopleDate(thing)
    if thing.is_a?(Date)
      MixpanelPeopleDate.new(thing)
    else
      thing
    end
  end
end

class MixpanelPeople
  def initialize(token, consumer=nil, &block)
    @token = token
    if block
      @sink = block
    elsif consumer
      @sink = consumer.method(:send)
    else
      consumer = MixpanelConsumer.new
      @sink = consumer.method(:send)
    end
  end

  def set(distinct_id, properties, ip=nil)
    properties = fix_property_dates(properties)
    update('$set', properties, distinct_id, ip)
  end

  def set_once(distinct_id, properties, ip=nil)
    properties = fix_property_dates(properties)
    update('$set_once', properties, distinct_id, ip)
  end

  def increment(distinct_id, properties, ip=nil)
    properties = fix_property_dates(properties)
    update('$add', properties, distinct_id, ip)
  end

  def append(distinct_id, properties, ip=nil)
    properties = fix_property_dates(properties)
    update('$append', properties, distinct_id, ip)
  end

  def union(distinct_id, properties, ip=nil)
    properties = fix_property_dates(properties)
    update('$union', properties, distinct_id, ip)
  end

  def track_charge(distinct_id, amount, properties, ip=nil)
    properties = fix_property_dates(properties)
    charge_properties = properties.merge({ '$amount' => amount })
    update('$append', { '$transactions' => charge_properties }, distinct_id, ip)
  end

  def clear_charges(distinct_id)
    update('$unset', [ '$transactions' ], distinct_id)
  end

  def delete_user(distinct_id)
    update('$delete', '', distinct_id)
  end

  def update(operation, operand, distinct_id, ip=nil)
    message = {
      '$token' => @token,
      '$distinct_id' => distinct_id,
      operation => operand
    }
    if ip
      message['$ip'] = ip
    end

    @sink.call(:profile_update, message.to_json)
  end

  private

  def fix_property_dates(h)
    h.inject({}) do |ret,(k,v)|
      ret[k] = MixpanelPeopleDate.asPeopleDate(v)
      ret
    end
  end
end

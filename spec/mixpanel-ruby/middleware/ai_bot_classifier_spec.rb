# spec/mixpanel-ruby/middleware/ai_bot_classifier_spec.rb
require 'spec_helper'
require 'rack'
require 'mixpanel-ruby/middleware/ai_bot_classifier'
require 'mixpanel-ruby/ai_bot_classifier'

describe Mixpanel::Middleware::AiBotClassifier do
  let(:inner_app) { ->(env) { [200, {}, ['OK']] } }
  let(:middleware) { described_class.new(inner_app) }

  after(:each) do
    Thread.current[:mixpanel_bot_classification] = nil
  end

  def make_request(user_agent: nil, remote_addr: '127.0.0.1')
    env = Rack::MockRequest.env_for('http://example.com/test', {
      'HTTP_USER_AGENT' => user_agent,
      'REMOTE_ADDR' => remote_addr,
    })
    middleware.call(env)
    env
  end

  describe 'request classification' do
    it 'classifies AI bot requests and stores in env' do
      env = make_request(user_agent: 'GPTBot/1.2')
      classification = env['mixpanel.bot_classification']

      expect(classification).not_to be_nil
      expect(classification[:is_ai_bot]).to be true
      expect(classification[:bot_name]).to eq('GPTBot')
      expect(classification[:provider]).to eq('OpenAI')
    end

    it 'classifies non-AI requests' do
      env = make_request(user_agent: 'Mozilla/5.0 Chrome/120')
      classification = env['mixpanel.bot_classification']

      expect(classification[:is_ai_bot]).to be false
    end

    it 'stores classification in Thread.current' do
      captured_classification = nil

      app = ->(env) {
        captured_classification = Thread.current[:mixpanel_bot_classification]
        [200, {}, ['OK']]
      }
      mw = described_class.new(app)

      env = Rack::MockRequest.env_for('/', {
        'HTTP_USER_AGENT' => 'GPTBot/1.2',
      })
      mw.call(env)

      expect(captured_classification).not_to be_nil
      expect(captured_classification[:is_ai_bot]).to be true
      expect(captured_classification[:bot_name]).to eq('GPTBot')
    end

    it 'cleans up Thread.current after request' do
      env = make_request(user_agent: 'GPTBot/1.2')
      expect(Thread.current[:mixpanel_bot_classification]).to be_nil
    end

    it 'cleans up Thread.current even if app raises' do
      app = ->(env) { raise RuntimeError, 'boom' }
      mw = described_class.new(app)

      env = Rack::MockRequest.env_for('/', {
        'HTTP_USER_AGENT' => 'GPTBot/1.2',
      })

      expect { mw.call(env) }.to raise_error(RuntimeError)
      expect(Thread.current[:mixpanel_bot_classification]).to be_nil
    end

    it 'handles missing User-Agent header' do
      env = make_request(user_agent: nil)
      classification = env['mixpanel.bot_classification']

      expect(classification[:is_ai_bot]).to be false
    end

    it 'stores IP address in classification' do
      env = make_request(
        user_agent: 'GPTBot/1.2',
        remote_addr: '1.2.3.4',
      )
      classification = env['mixpanel.bot_classification']

      expect(classification[:ip]).to eq('1.2.3.4')
    end

    it 'extracts IP from X-Forwarded-For when present' do
      env = Rack::MockRequest.env_for('/', {
        'HTTP_USER_AGENT' => 'GPTBot/1.2',
        'HTTP_X_FORWARDED_FOR' => '5.6.7.8, 9.10.11.12',
        'REMOTE_ADDR' => '127.0.0.1',
      })
      middleware.call(env)
      classification = env['mixpanel.bot_classification']

      expect(classification[:ip]).to eq('5.6.7.8')
    end
  end

  describe 'passthrough behavior' do
    it 'passes the request through to the inner app' do
      status, _headers, body = middleware.call(
        Rack::MockRequest.env_for('/', {
          'HTTP_USER_AGENT' => 'GPTBot/1.2',
        })
      )
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end

    it 'does not modify the response' do
      app = ->(env) { [201, { 'X-Custom' => 'value' }, ['Created']] }
      mw = described_class.new(app)

      status, headers, body = mw.call(
        Rack::MockRequest.env_for('/', {
          'HTTP_USER_AGENT' => 'Chrome/120',
        })
      )

      expect(status).to eq(201)
      expect(headers['X-Custom']).to eq('value')
      expect(body).to eq(['Created'])
    end
  end
end

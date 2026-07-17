# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DevtoAnalytics::APIClient do
  let(:conn) { instance_double(Faraday::Connection) }
  let(:client) { described_class.new(api_key: 'test-key') }

  before do
    allow(Faraday).to receive(:new).and_return(conn)
  end

  def fake_response(body)
    instance_double(Faraday::Response, body: JSON.generate(body))
  end

  describe '#analytics_totals' do
    it 'requests without organization_id when none is given' do
      expect(conn).to receive(:get)
        .with('/api/analytics/totals', { article_id: 123 }, hash_including('api-key' => 'test-key'))
        .and_return(fake_response('page_views' => { 'total' => 5 }))

      result = client.analytics_totals(123)
      expect(result['page_views']['total']).to eq(5)
    end

    it 'includes organization_id when given, to authorize non-owned articles' do
      expect(conn).to receive(:get)
        .with('/api/analytics/totals', { article_id: 123, organization_id: 2526 }, anything)
        .and_return(fake_response('page_views' => { 'total' => 238 }))

      result = client.analytics_totals(123, organization_id: 2526)
      expect(result['page_views']['total']).to eq(238)
    end
  end

  describe '#analytics_historical' do
    it 'includes organization_id alongside start when given' do
      expect(conn).to receive(:get)
        .with('/api/analytics/historical', { article_id: 123, start: '2026-01-01', organization_id: 2526 }, anything)
        .and_return(fake_response({}))

      client.analytics_historical(123, since: '2026-01-01', organization_id: 2526)
    end
  end

  describe '#get_organization' do
    it 'parses the organization payload' do
      expect(conn).to receive(:get)
        .with('/api/organizations/puppet', {}, anything)
        .and_return(fake_response('id' => 2526, 'username' => 'puppet'))

      result = client.get_organization('puppet')
      expect(result['id']).to eq(2526)
    end
  end

  describe 'rate limiting' do
    before { allow(client).to receive(:sleep) }

    def rate_limited(retry_after: nil)
      headers = retry_after ? { 'Retry-After' => retry_after } : {}
      Faraday::TooManyRequestsError.new('rate limited', { status: 429, headers: headers })
    end

    it 'paces consecutive requests to stay under the read throttle' do
      allow(conn).to receive(:get).and_return(fake_response({}))

      client.analytics_totals(1)
      client.analytics_totals(2)

      expect(client).to have_received(:sleep)
        .with(a_value_within(0.05).of(described_class::MIN_REQUEST_INTERVAL)).once
    end

    it 'honors the Retry-After header on a 429, then succeeds' do
      attempt = 0
      allow(conn).to receive(:get) do
        attempt += 1
        raise rate_limited(retry_after: '3') if attempt == 1

        fake_response('page_views' => { 'total' => 42 })
      end

      result = client.analytics_totals(1)

      expect(client).to have_received(:sleep).with(3.0)
      expect(result['page_views']['total']).to eq(42)
    end

    it 'falls back to exponential backoff when no Retry-After header is present' do
      attempt = 0
      allow(conn).to receive(:get) do
        attempt += 1
        raise rate_limited if attempt == 1

        fake_response('page_views' => { 'total' => 7 })
      end

      client.analytics_totals(1)

      expect(client).to have_received(:sleep).with(described_class::DEFAULT_INITIAL_BACKOFF)
    end

    it 'gives up and returns nil after exhausting max_retries on repeated 429s' do
      allow(conn).to receive(:get).and_raise(rate_limited)

      result = client.analytics_totals(1)
      last_backoff = described_class::DEFAULT_INITIAL_BACKOFF * (2**(described_class::DEFAULT_MAX_RETRIES - 1))

      expect(result).to be_nil
      expect(client).to have_received(:sleep).with(described_class::DEFAULT_INITIAL_BACKOFF)
      expect(client).to have_received(:sleep).with(last_backoff)
    end
  end
end

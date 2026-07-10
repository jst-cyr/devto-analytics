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
end

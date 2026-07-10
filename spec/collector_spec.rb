# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DevtoAnalytics::Collector do
  let(:client) { instance_double(DevtoAnalytics::APIClient) }
  let(:collector) { described_class.new(org: 'puppet', since: '2025-06-01', out_dir: 'tmp_spec_out') }

  before do
    allow(DevtoAnalytics::APIClient).to receive(:new).and_return(client)
  end

  describe '#organization_id' do
    it 'resolves and memoizes the numeric id from the API' do
      expect(client).to receive(:get_organization).with('puppet').once.and_return('id' => 2526)

      expect(collector.organization_id).to eq(2526)
      expect(collector.organization_id).to eq(2526) # memoized, no second API call
    end

    it 'prefers DEVTO_ORG_ID when set, skipping the API lookup' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DEVTO_ORG_ID').and_return('9999')
      expect(client).not_to receive(:get_organization)

      expect(collector.organization_id).to eq('9999')
    end
  end

  describe '#run' do
    it 'passes organization_id on every analytics_totals call, so non-owned articles get readers too' do
      article = {
        'id' => 3_652_706,
        'title' => 'Handling Dirty Frag and Copy Fail with Puppet',
        'url' => 'https://dev.to/puppet/handling-dirty-frag-and-copy-fail-with-puppet-6ff',
        'published_at' => '2026-05-13T21:00:55Z'
      }

      allow(client).to receive(:list_articles).and_return([article], [])
      allow(client).to receive(:get_organization).with('puppet').and_return('id' => 2526)
      expect(client).to receive(:analytics_totals)
        .with(3_652_706, organization_id: 2526)
        .and_return('page_views' => { 'total' => 238 }, 'reactions' => { 'total' => 4 }, 'comments' => { 'total' => 0 })

      result = collector.run(write: false)

      row = result[:rows].first
      expect(row['readers']).to eq(238)
    end
  end
end

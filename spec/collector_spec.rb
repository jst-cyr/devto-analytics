# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'

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

      result = collector.run(write: false, weekly: false)

      row = result[:rows].first
      expect(row['readers']).to eq(238)
    end
  end

  describe 'skipping organization_id for owned articles' do
    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('DEVTO_USERNAME', anything).and_return('jasonstcyr')
    end

    it 'omits organization_id when DEVTO_USERNAME matches the article author (cheaper, less-throttled path)' do
      article = {
        'id' => 111,
        'title' => 'My Own Post',
        'url' => 'https://dev.to/puppet/my-own-post',
        'published_at' => '2026-05-13T21:00:55Z',
        'user' => { 'username' => 'jasonstcyr' }
      }

      allow(client).to receive(:list_articles).and_return([article], [])
      allow(client).to receive(:get_organization).with('puppet').and_return('id' => 2526)
      expect(client).to receive(:analytics_totals)
        .with(111, organization_id: nil)
        .and_return('page_views' => { 'total' => 50 })

      result = collector.run(write: false, weekly: false)
      expect(result[:rows].first['readers']).to eq(50)
    end

    it 'still passes organization_id when the article was authored by someone else' do
      article = {
        'id' => 222,
        'title' => "Someone Else's Post",
        'url' => 'https://dev.to/puppet/someone-elses-post',
        'published_at' => '2026-05-13T21:00:55Z',
        'user' => { 'username' => 'albatrossflavour' }
      }

      allow(client).to receive(:list_articles).and_return([article], [])
      allow(client).to receive(:get_organization).with('puppet').and_return('id' => 2526)
      expect(client).to receive(:analytics_totals)
        .with(222, organization_id: 2526)
        .and_return('page_views' => { 'total' => 20 })

      result = collector.run(write: false, weekly: false)
      expect(result[:rows].first['readers']).to eq(20)
    end
  end

  describe 'the recent-window CSV written alongside the totals CSV' do
    let(:out_dir) { Dir.mktmpdir }
    let(:today) { Time.now.utc.strftime('%Y-%m-%d') }
    let(:collector) { described_class.new(org: 'puppet', since: '2025-06-01', out_dir: out_dir) }
    let(:article) do
      { 'id' => 7, 'title' => 'A', 'url' => 'https://a', 'published_at' => '2025-06-02T00:00:00Z' }
    end

    after { FileUtils.remove_entry(out_dir) }

    before do
      allow(client).to receive(:list_articles).and_return([article], [])
      allow(client).to receive(:get_organization).with('puppet').and_return('id' => 2526)
      allow(client).to receive(:analytics_totals).and_return('page_views' => { 'total' => 238 })
    end

    it 'writes both CSVs, the second scoped to the window and the first still lifetime totals' do
      window_start = (Time.now.utc.to_date - 6).to_s
      expect(client).to receive(:analytics_historical)
        .with(7, since: window_start, organization_id: 2526)
        .and_return(window_start => { 'page_views' => { 'total' => 12 } })

      collector.run(write: true)

      totals = CSV.read(File.join(out_dir, today, "puppet-analytics-#{today}.csv"), headers: true)
      window = CSV.read(File.join(out_dir, today, "puppet-window-#{today}.csv"), headers: true)

      expect(totals.first['readers']).to eq('238')
      expect(window.first['readers']).to eq('12')
      expect(window.first['window_start']).to eq(window_start)
      expect(window.first['window_end']).to eq(today)
    end

    it 'honours a custom window length' do
      expect(client).to receive(:analytics_historical)
        .with(7, since: (Time.now.utc.to_date - 29).to_s, organization_id: 2526)
        .and_return({})

      collector.run(write: true, weekly_days: 30)
    end

    it 'skips the second pass entirely when weekly is off' do
      expect(client).not_to receive(:analytics_historical)

      result = collector.run(write: true, weekly: false)

      expect(result[:weekly_rows]).to be_nil
      expect(File.exist?(File.join(out_dir, today, "puppet-window-#{today}.csv"))).to be(false)
    end
  end

  describe 'resuming an existing day\'s output' do
    let(:out_dir) { Dir.mktmpdir }
    let(:today) { Time.now.utc.strftime('%Y-%m-%d') }
    let(:collector) { described_class.new(org: 'puppet', since: '2025-06-01', out_dir: out_dir) }

    after { FileUtils.remove_entry(out_dir) }

    def write_existing_json(records)
      dir = File.join(out_dir, today)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "puppet-analytics-#{today}.json"), JSON.generate(records))
    end

    it 'does nothing and reports done when every existing record already has readers' do
      records = [
        { 'article' => { 'id' => 1, 'title' => 'A', 'url' => 'https://a', 'published_at' => '2025-06-02T00:00:00Z' },
          'totals' => { 'page_views' => { 'total' => 10 } } }
      ]
      write_existing_json(records)

      expect(client).not_to receive(:list_articles)
      expect(client).not_to receive(:get_organization)
      expect(client).not_to receive(:analytics_totals)

      result = collector.run(write: true, weekly: false)

      expect(result[:records]).to eq(records)
    end

    it 'retries only the articles missing readers, leaving successful ones untouched' do
      records = [
        { 'article' => { 'id' => 1, 'title' => 'A', 'url' => 'https://a', 'published_at' => '2025-06-02T00:00:00Z' },
          'totals' => { 'page_views' => { 'total' => 10 } } },
        { 'article' => { 'id' => 2, 'title' => 'B', 'url' => 'https://b', 'published_at' => '2025-06-03T00:00:00Z' },
          'totals' => nil }
      ]
      write_existing_json(records)

      expect(client).not_to receive(:list_articles)
      allow(client).to receive(:get_organization).with('puppet').and_return('id' => 2526)
      expect(client).to receive(:analytics_totals)
        .with(2, organization_id: 2526)
        .and_return('page_views' => { 'total' => 99 })

      result = collector.run(write: true, weekly: false)

      readers_by_id = result[:rows].to_h { |r| [r['id'], r['readers']] }
      expect(readers_by_id).to eq(1 => 10, 2 => 99)
    end
  end
end

# frozen_string_literal: true

require 'spec_helper'
require 'date'

RSpec.describe DevtoAnalytics::WeeklyCollector do
  let(:client) { instance_double(DevtoAnalytics::APIClient) }
  let(:today) { Date.new(2026, 7, 31) }
  let(:article) do
    { 'id' => 3_652_706, 'title' => 'Handling Dirty Frag and Copy Fail with Puppet',
      'url' => 'https://dev.to/puppet/handling-dirty-frag', 'published_at' => '2026-05-13T21:00:55Z' }
  end

  def day(views:, read_time: 0, reactions: 0, comments: 0, follows: 0)
    { 'page_views' => { 'total' => views, 'total_read_time_in_seconds' => read_time },
      'reactions' => { 'total' => reactions }, 'comments' => { 'total' => comments },
      'follows' => { 'total' => follows } }
  end

  describe 'the window boundaries' do
    it 'spans exactly `days` whole calendar dates ending on the current date' do
      collector = described_class.new(client: client, days: 7, today: today)

      expect(collector.window_start).to eq(Date.new(2026, 7, 25))
      expect(collector.window_end).to eq(today)
      expect((collector.window_start..collector.window_end).count).to eq(7)
    end

    it 'does not shift with the time of day, only the date' do
      morning = described_class.new(client: client, days: 7, today: today)
      evening = described_class.new(client: client, days: 7, today: today)

      expect(evening.label).to eq(morning.label)
      expect(morning.label).to eq('2026-07-25..2026-07-31')
    end

    it 'rejects a non-positive window' do
      expect { described_class.new(client: client, days: 0, today: today) }.to raise_error(ArgumentError)
    end
  end

  describe '#collect' do
    it 'requests history from the window start and sums each metric over the window' do
      expect(client).to receive(:analytics_historical)
        .with(3_652_706, since: '2026-07-25', organization_id: nil)
        .and_return('2026-07-25' => day(views: 10, read_time: 60, reactions: 1),
                    '2026-07-28' => day(views: 20, read_time: 120, follows: 2),
                    '2026-07-31' => day(views: 5, read_time: 30, comments: 3))

      rows, records = described_class.new(client: client, days: 7, today: today).collect([article])

      row = rows.first
      expect(row['readers']).to eq(35)
      expect(row['read_time_seconds']).to eq(210)
      expect(row['reactions']).to eq(1)
      expect(row['comments']).to eq(3)
      expect(row['follows']).to eq(2)
      expect(row['window_start']).to eq('2026-07-25')
      expect(row['window_end']).to eq('2026-07-31')
      expect(records.first['history'].keys).to contain_exactly('2026-07-25', '2026-07-28', '2026-07-31')
    end

    it 'drops days the API returns outside the requested window' do
      allow(client).to receive(:analytics_historical)
        .and_return('2026-07-24' => day(views: 500), # before window_start
                    '2026-07-26' => day(views: 7),
                    '2026-08-02' => day(views: 900)) # after window_end

      rows, = described_class.new(client: client, days: 7, today: today).collect([article])

      expect(rows.first['readers']).to eq(7)
    end

    it 'reports zero for a genuinely quiet week' do
      allow(client).to receive(:analytics_historical)
        .and_return('2026-07-25' => day(views: 0), '2026-07-26' => day(views: 0))

      rows, = described_class.new(client: client, days: 7, today: today).collect([article])

      expect(rows.first['readers']).to eq(0)
    end

    it 'leaves metrics blank rather than zero when the fetch fails, so it cannot read as a quiet week' do
      allow(client).to receive(:analytics_historical).and_return(nil)

      rows, records = described_class.new(client: client, days: 7, today: today).collect([article])

      expect(rows.first['readers']).to be_nil
      expect(rows.first['reactions']).to be_nil
      expect(records.first['history']).to be_nil
    end

    it 'treats an error payload as a failure, not as data' do
      allow(client).to receive(:analytics_historical)
        .and_return('error' => "You can't view this article's stats")

      rows, = described_class.new(client: client, days: 7, today: today).collect([article])

      expect(rows.first['readers']).to be_nil
    end

    it 'passes the scoped organization id the block supplies' do
      expect(client).to receive(:analytics_historical)
        .with(3_652_706, since: '2026-07-25', organization_id: 2526)
        .and_return({})

      described_class.new(client: client, days: 7, today: today,
                          scope: ->(_a) { 2526 }).collect([article])
    end
  end

  describe 'reusing a previous run' do
    let(:other) { { 'id' => 999, 'title' => 'B', 'url' => 'https://b', 'published_at' => '2026-01-01T00:00:00Z' } }

    it 'skips articles whose history already succeeded and retries the ones that failed' do
      existing = [
        { 'article' => article, 'history' => { '2026-07-26' => day(views: 40) } },
        { 'article' => other, 'history' => nil }
      ]

      expect(client).not_to receive(:analytics_historical).with(3_652_706, any_args)
      expect(client).to receive(:analytics_historical)
        .with(999, since: '2026-07-25', organization_id: nil)
        .and_return('2026-07-27' => day(views: 3))

      rows, = described_class.new(client: client, days: 7, today: today)
                             .collect([article, other], existing: existing)

      readers = rows.to_h { |r| [r['id'], r['readers']] }
      expect(readers).to eq(3_652_706 => 40, 999 => 3)
    end
  end
end

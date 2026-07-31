# frozen_string_literal: true

require 'date'

module DevtoAnalytics
  # Aggregates Forem's per-day `/api/analytics/historical` data into a single
  # fixed window of whole calendar days.
  #
  # The window is derived from UTC *dates*, not from a rolling interval measured
  # back from the moment the run starts, so every run on a given day covers
  # exactly the same period no matter what time of day it happens.
  #
  # Unlike `/api/analytics/totals` (lifetime counters, which only yield a period
  # by diffing two daily snapshots), this reports the traffic that actually
  # occurred inside the window — immune to snapshot timing drift and to a
  # previous day's failed fetches recovering later and looking like a spike.
  class WeeklyCollector
    DEFAULT_DAYS = 7

    attr_reader :window_start, :window_end

    # `paths` takes :csv and :json destinations for #run to write to.
    def initialize(client:, days: DEFAULT_DAYS, scope: nil, paths: {}, today: nil)
      days = days.to_i
      raise ArgumentError, "days must be positive, got #{days}" unless days.positive?

      @client = client
      @scope = scope || ->(_article) {}
      @csv_path = paths[:csv]
      @json_path = paths[:json]
      @window_end = today || Time.now.utc.to_date
      @window_start = @window_end - (days - 1)
    end

    def label
      "#{@window_start}..#{@window_end}"
    end

    # Collect, summarize, and write in one step. Returns [rows, records].
    def run(articles, existing: nil, write: true)
      puts "Collecting window #{label} for #{articles.size} articles"
      rows, records = collect(articles, existing: existing)
      report_summary(rows)
      write ? write_outputs(rows, records) : puts("Dry run: would write #{rows.size} window rows")

      [rows, records]
    end

    # Records keep the raw per-day payload so a repeat run can reuse it, and so
    # a genuinely quiet week stays distinguishable from a fetch that failed.
    def collect(articles, existing: nil)
      reusable = index_history(existing)
      rows = []
      records = []

      articles.each_with_index do |article, idx|
        history = reusable.fetch(article['id']) { fetch_history(article) }
        rows << build_row(article, history)
        records << { 'article' => article, 'history' => history }
        report_progress(idx + 1, articles.size, article['id'], history)
      end

      [rows, records]
    end

    private

    # Only Hash histories are reusable; a nil means the earlier attempt failed
    # (usually 429 retries exhausted) and should be tried again.
    def index_history(existing)
      return {} unless existing.is_a?(Array)

      existing.each_with_object({}) do |record, acc|
        id = record.dig('article', 'id')
        history = record['history']
        acc[id] = history if id && history.is_a?(Hash)
      end
    end

    def fetch_history(article)
      raw = @client.analytics_historical(article['id'], since: @window_start.to_s,
                                                        organization_id: @scope.call(article))
      return nil unless raw.is_a?(Hash)
      return nil if raw.key?('error')

      within_window(raw)
    rescue StandardError => e
      warn "Error fetching history for article #{article['id']}: #{e.message}"
      nil
    end

    # The endpoint returns every day from `start` through today; keep only the
    # dates the window asked for, in case that range is wider than requested.
    def within_window(raw)
      raw.select { |date, value| value.is_a?(Hash) && in_range?(date) }
    end

    def in_range?(date)
      Date.iso8601(date.to_s).between?(@window_start, @window_end)
    rescue Date::Error
      false
    end

    def build_row(article, history)
      {
        'id' => article['id'],
        'title' => article['title'],
        'url' => article['url'] || article['canonical_url'] || article['path'],
        'published_at' => article['published_at'] || article['published_timestamp'],
        'window_start' => @window_start.to_s,
        'window_end' => @window_end.to_s
      }.merge(metric_columns(history))
    end

    # Leaves metrics blank (nil) rather than 0 when the fetch failed, so an
    # unavailable article can't be misread as a week with no traffic.
    def metric_columns(history)
      days = history || {}

      {
        'readers' => history && sum(days, 'page_views', 'total'),
        'read_time_seconds' => history && sum(days, 'page_views', 'total_read_time_in_seconds'),
        'reactions' => history && sum(days, 'reactions', 'total'),
        'comments' => history && sum(days, 'comments', 'total'),
        'follows' => history && sum(days, 'follows', 'total')
      }
    end

    def sum(days, group, key)
      days.sum { |_date, value| value.dig(group, key).to_i }
    end

    def report_progress(index, total, article_id, history)
      status = history.is_a?(Hash) ? "ok readers=#{sum(history, 'page_views', 'total')}" : 'FAIL'
      puts "[#{index}/#{total}] #{status} id=#{article_id} (#{label})"
    end

    def report_summary(rows)
      failed = rows.count { |r| r['readers'].nil? }
      summary = "Window #{label}: #{rows.sum { |r| r['readers'].to_i }} readers across #{rows.size} articles"
      summary += " (#{failed} failed to fetch)" if failed.positive?
      puts summary
    end

    # The window CSV is always written, regardless of the totals run's `format`
    # — it's the whole point of the second pass. The JSON beside it carries the
    # raw per-day payloads so a re-run can skip articles that already succeeded.
    def write_outputs(rows, records)
      FileUtils.mkdir_p(File.dirname(@csv_path))
      Formatter.write_weekly_csv(@csv_path, rows)
      Formatter.write_json(@json_path, records)
      puts "Wrote #{@csv_path}"
      puts "Wrote #{@json_path}"
    end
  end
end

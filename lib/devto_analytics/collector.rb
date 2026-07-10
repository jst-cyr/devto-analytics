# frozen_string_literal: true

require 'time'
require 'fileutils'

module DevtoAnalytics
  # Fetches an org's articles and per-article analytics, then formats them
  # into CSV/JSON rows.
  class Collector
    def initialize(org:, since:, out_dir: ENV['OUTPUT_DIR'] || 'data')
      @org = org
      @since = since
      @out_dir = out_dir
      @client = APIClient.new
    end

    def list_articles_page(page: 1, per_page: 10)
      @client.list_articles(@org, per_page: per_page, page: page) || []
    end

    # Resolves the org's numeric id, needed to pull analytics for articles
    # authored by other org members. Memoized; falls back to nil (analytics
    # will then only succeed for articles authored by the API key's own user).
    def organization_id
      return @organization_id if defined?(@organization_id)

      @organization_id = ENV['DEVTO_ORG_ID'] || begin
        org = @client.get_organization(@org)
        org && org['id']
      end
    end

    def all_articles(per_page: 10)
      page = 1
      results = []
      loop do
        batch = list_articles_page(page: page, per_page: per_page)
        break if batch.nil? || batch.empty?

        # Assume API returns newest-first. We'll stop paging once we detect
        # that further pages will only contain articles older than the `since` cutoff.
        results.concat(batch)

        break if batch.size < per_page || page_before_since?(batch)

        page += 1
      end

      results
    end

    def run(write: true, format: 'csv')
      puts "Collecting articles for org=#{@org} since=#{@since}"
      articles = all_articles(per_page: 100)
      puts "Found #{articles.size} articles total (fetched pages)"

      since_time = safe_parse_time(@since)
      org_id = organization_id
      rows = []
      records = []

      articles.each do |a|
        published = a['published_at'] || a['published_timestamp']
        next if published.nil? || before_since?(published, since_time)

        totals = fetch_totals(a['id'], org_id)
        rows << build_row(a, published, totals)
        records << { 'article' => a, 'totals' => totals }
      end

      write ? write_outputs(rows, records, format) : puts("Dry run: would write #{rows.size} rows")

      { articles: articles, rows: rows, records: records }
    end

    private

    def safe_parse_time(str)
      Time.parse(str)
    rescue StandardError
      nil
    end

    # Whether the last article in a fetched page is older than `@since`,
    # meaning further (older) pages can't contain anything relevant.
    def page_before_since?(batch)
      return false unless @since

      since_time = safe_parse_time(@since)
      return false unless since_time

      last_pub = batch.last && (batch.last['published_at'] || batch.last['published_timestamp'])
      return false unless last_pub

      last_time = safe_parse_time(last_pub)
      !last_time.nil? && last_time < since_time
    end

    def before_since?(published, since_time)
      return false unless since_time

      pub_time = safe_parse_time(published)
      # If parsing fails, include the article conservatively.
      !pub_time.nil? && pub_time < since_time
    end

    def fetch_totals(article_id, org_id)
      @client.analytics_totals(article_id, organization_id: org_id)
    rescue StandardError => e
      warn "Error fetching totals for article #{article_id}: #{e.message}"
      nil
    end

    def build_row(article, published, totals)
      metrics = extract_metrics(totals)

      {
        'id' => article['id'],
        'title' => article['title'],
        'url' => article['url'] || article['canonical_url'] || article['path'],
        'published_at' => published,
        'readers' => metrics[:readers],
        'reactions' => metrics[:reactions] || article['positive_reactions_count'] || article['public_reactions_count'],
        'comments' => metrics[:comments] || article['comments_count']
      }
    end

    def extract_metrics(totals)
      return {} unless totals.is_a?(Hash)

      metrics = {}
      metrics[:readers] = totals['page_views']['total'] if totals['page_views'].is_a?(Hash)
      if totals['reactions'].is_a?(Hash)
        metrics[:reactions] = totals['reactions']['total'] || totals['reactions']['like']
      end
      metrics[:comments] = totals['comments']['total'] if totals['comments'].is_a?(Hash)
      metrics
    end

    def write_outputs(rows, records, format)
      timestamp = Time.now.utc.strftime('%Y-%m-%d')
      dir = File.join(@out_dir, timestamp)
      FileUtils.mkdir_p(dir)
      csv_path = File.join(dir, "#{@org}-analytics-#{timestamp}.csv")
      json_path = File.join(dir, "#{@org}-analytics-#{timestamp}.json")

      if format.downcase == 'json'
        Formatter.write_json(json_path, records)
      else
        Formatter.write_csv(csv_path, rows)
        Formatter.write_json(json_path, records)
        puts "Wrote #{csv_path}"
      end
      puts "Wrote #{json_path}"
    end
  end
end

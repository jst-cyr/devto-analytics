# frozen_string_literal: true

require 'time'
require 'fileutils'
require 'json'

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

    # Organization-scoped analytics queries measurably throttle harder than
    # user-scoped ones under load (empirically: ~4x more 429s in a same-size
    # concurrent burst), so only pass organization_id for articles we don't
    # already own. Requires DEVTO_USERNAME to be set; without it, falls back
    # to always scoping by org (the old, safer-but-slower behavior).
    def org_id_for(article, org_id)
      my_username = ENV.fetch('DEVTO_USERNAME', nil)
      return org_id unless my_username

      author = article['user'] && article['user']['username']
      author&.casecmp?(my_username) ? nil : org_id
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
      $stdout.sync = true
      timestamp = Time.now.utc.strftime('%Y-%m-%d')
      csv_path, json_path = output_paths(timestamp)

      if write
        existing = load_existing_records(json_path)
        return resume(existing, csv_path, json_path, format) if existing
      end

      full_run(write, format, csv_path, json_path)
    end

    private

    def full_run(write, format, csv_path, json_path)
      puts "Collecting articles for org=#{@org} since=#{@since}"
      articles = all_articles(per_page: 100)
      matching = matching_articles(articles)
      puts "Found #{articles.size} articles total (fetched pages); #{matching.size} match since=#{@since}"

      rows, records = process_articles(matching)

      write ? write_outputs(rows, records, format, csv_path, json_path) : puts("Dry run: would write #{rows.size} rows")

      { articles: articles, rows: rows, records: records }
    end

    # Picks up a previous run's output for today: articles that already have
    # readers are left untouched, and only the ones that failed (almost always
    # due to 429s exhausting their retries) are re-fetched. Avoids re-listing
    # articles or re-querying analytics that already succeeded.
    def resume(records, csv_path, json_path, format)
      incomplete = records.reject { |r| readers_present?(r['totals']) }

      if incomplete.empty?
        puts "#{csv_path} already complete (#{records.size} articles all have readers) — nothing to do."
        return { articles: records.map { |r| r['article'] }, rows: nil, records: records }
      end

      retry_incomplete(records, incomplete, csv_path)
      rows = records.map { |r| build_row(r['article'], article_published(r['article']), r['totals']) }

      write_outputs(rows, records, format, csv_path, json_path)
      { articles: records.map { |r| r['article'] }, rows: rows, records: records }
    end

    def retry_incomplete(records, incomplete, csv_path)
      puts "Resuming #{File.basename(csv_path)}: #{incomplete.size}/#{records.size} " \
           'articles missing readers, retrying those.'
      org_id = organization_id
      by_id = index_by_article_id(records)

      incomplete.each_with_index do |record, idx|
        article_id = record['article']['id']
        refresh_totals(by_id, article_id, org_id)
        report_progress(idx + 1, incomplete.size, article_id, by_id[article_id]['totals'])
      end
    end

    def index_by_article_id(records)
      records.each_with_object({}) { |r, h| h[r['article']['id']] = r }
    end

    def refresh_totals(by_id, article_id, org_id)
      article = by_id[article_id]['article']
      totals = fetch_totals(article_id, org_id_for(article, org_id))
      by_id[article_id]['totals'] = totals if totals.is_a?(Hash)
    end

    def readers_present?(totals)
      !extract_metrics(totals)[:readers].nil?
    end

    def article_published(article)
      article['published_at'] || article['published_timestamp']
    end

    def load_existing_records(json_path)
      return nil unless File.exist?(json_path)

      JSON.parse(File.read(json_path))
    rescue StandardError => e
      warn "Could not read existing #{json_path}, running fresh: #{e.message}"
      nil
    end

    def output_paths(timestamp)
      dir = File.join(@out_dir, timestamp)
      [
        File.join(dir, "#{@org}-analytics-#{timestamp}.csv"),
        File.join(dir, "#{@org}-analytics-#{timestamp}.json")
      ]
    end

    def safe_parse_time(str)
      Time.parse(str)
    rescue StandardError
      nil
    end

    def matching_articles(articles)
      since_time = safe_parse_time(@since)
      articles.reject { |a| skip_article?(a, since_time) }
    end

    def skip_article?(article, since_time)
      published = article_published(article)
      published.nil? || before_since?(published, since_time)
    end

    def process_articles(matching)
      org_id = organization_id
      rows = []
      records = []

      matching.each_with_index do |a, idx|
        published = article_published(a)
        totals = fetch_totals(a['id'], org_id_for(a, org_id))
        rows << build_row(a, published, totals)
        records << { 'article' => a, 'totals' => totals }
        report_progress(idx + 1, matching.size, a['id'], totals)
      end

      [rows, records]
    end

    def report_progress(index, total, article_id, totals)
      status = totals.is_a?(Hash) ? 'ok' : 'FAIL'
      puts "[#{index}/#{total}] #{status} id=#{article_id}"
    end

    # Whether the last article in a fetched page is older than `@since`,
    # meaning further (older) pages can't contain anything relevant.
    def page_before_since?(batch)
      return false unless @since

      since_time = safe_parse_time(@since)
      return false unless since_time

      last_pub = batch.last && article_published(batch.last)
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

    def write_outputs(rows, records, format, csv_path, json_path)
      FileUtils.mkdir_p(File.dirname(csv_path))

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

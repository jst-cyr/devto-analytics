require 'time'
require 'fileutils'

module DevtoAnalytics
  class Collector
    def initialize(org:, since:, out_dir: ENV['OUTPUT_DIR'] || 'data')
      @org = org
      @since = since
      @out_dir = out_dir
      @client = APIClient.new
    end

    def list_articles
      # For the skeleton, only fetch first page
      @client.list_articles(@org, per_page: 100, page: 1)
    end

    def run(write: true, format: 'csv')
      puts "Collecting articles for org=#{@org} since=#{@since}"
      articles = list_articles || []
      puts "Found #{articles.size} articles (first page)"

      # Capture minimal rows for skeleton: id, url, published_at
      rows = articles.map do |a|
        {
          'id' => a['id'],
          'url' => a['url'] || a['path'] || a['canonical_url'],
          'published_at' => a['published_at'] || a['published_timestamp']
        }
      end

      if write
        timestamp = Time.now.utc.strftime('%Y-%m-%d')
        dir = File.join(@out_dir, timestamp)
        FileUtils.mkdir_p(dir)
        filename = File.join(dir, "#{@org}-analytics-#{timestamp}.csv")
        Formatter.write_csv(filename, rows)
        puts "Wrote #{filename}"
      else
        puts "Dry run: would write #{rows.size} rows"
      end

      { articles: articles, rows: rows }
    end
  end
end

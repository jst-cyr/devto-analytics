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

    def list_articles_page(page: 1, per_page: 10)
      @client.list_articles(@org, per_page: per_page, page: page) || []
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

        break if batch.size < per_page

        # If a since date is set and the last article in this page is older than
        # the cutoff, we can stop (no need to fetch older pages).
        if @since
          begin
            since_time = Time.parse(@since)
            last = batch.last
            last_pub = last && (last['published_at'] || last['published_timestamp'])
            if last_pub
              last_time = Time.parse(last_pub)
              break if last_time < since_time
            end
          rescue StandardError
            # parsing failed; continue conservative paging
          end
        end

        page += 1
      end

      results
    end

    def run(write: true, format: 'csv')
      puts "Collecting articles for org=#{@org} since=#{@since}"
      articles = all_articles(per_page: 100)
      puts "Found #{articles.size} articles total (fetched pages)"

      # Filter by since if provided
      since_time = begin
        Time.parse(@since)
      rescue StandardError
        nil
      end

      rows = []
      records = []

      articles.each do |a|
        published = a['published_at'] || a['published_timestamp']
        next if published.nil?
        if since_time
          begin
            pub_time = Time.parse(published)
            next if pub_time < since_time
          rescue StandardError
            # If parsing fails, include the article conservatively
          end
        end

        article_id = a['id']
        title = a['title']
        url = a['url'] || a['canonical_url'] || a['path']

        # Try analytics totals (may return nil if unauthorized)
        totals = nil
        begin
          totals = @client.analytics_totals(article_id)
        rescue StandardError => e
          warn "Error fetching totals for article #{article_id}: #{e.message}"
          totals = nil
        end

        readers = nil
        reactions = nil
        comments = nil

        if totals && totals.is_a?(Hash)
          if totals['page_views'] && totals['page_views'].is_a?(Hash)
            readers = totals['page_views']['total']
          end
          if totals['reactions'] && totals['reactions'].is_a?(Hash)
            reactions = totals['reactions']['total'] || totals['reactions']['like']
          end
          if totals['comments'] && totals['comments'].is_a?(Hash)
            comments = totals['comments']['total']
          end
        end

        # Fallbacks from article metadata if analytics not available
        reactions ||= a['positive_reactions_count'] || a['public_reactions_count']
        comments ||= a['comments_count']

        row = {
          'id' => article_id,
          'title' => title,
          'url' => url,
          'published_at' => published,
          'readers' => readers,
          'reactions' => reactions,
          'comments' => comments
        }

        rows << row

        # For JSON output, include article metadata and totals
        records << { 'article' => a, 'totals' => totals }
      end

      if write
        timestamp = Time.now.utc.strftime('%Y-%m-%d')
        dir = File.join(@out_dir, timestamp)
        FileUtils.mkdir_p(dir)
        csv_path = File.join(dir, "#{@org}-analytics-#{timestamp}.csv")
        json_path = File.join(dir, "#{@org}-analytics-#{timestamp}.json")

        if format.downcase == 'json'
          Formatter.write_json(json_path, records)
          puts "Wrote #{json_path}"
        else
          Formatter.write_csv(csv_path, rows)
          Formatter.write_json(json_path, records)
          puts "Wrote #{csv_path}"
          puts "Wrote #{json_path}"
        end
      else
        puts "Dry run: would write #{rows.size} rows"
      end

      { articles: articles, rows: rows, records: records }
    end
  end
end

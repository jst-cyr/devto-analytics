require 'thor'

module DevtoAnalytics
  class CLI < Thor
    desc 'fetch', 'Fetch analytics for an organization (delegates to Collector)'
    option :org, type: :string, desc: 'Organization slug (overrides DEVTO_ORG_SLUG)'
    option :since, type: :string, desc: 'ISO start date (overrides DEVTO_SINCE)'
    option :format, type: :string, default: 'csv', desc: 'Output format: csv or json'
    option :out_dir, type: :string, desc: 'Output directory (overrides OUTPUT_DIR)'
    def fetch
      org = options[:org] || ENV['DEVTO_ORG_SLUG']
      raise Thor::RequiredArgumentMissingError, "No organization provided. Use --org or set DEVTO_ORG_SLUG." unless org
      since = options[:since] || ENV['DEVTO_SINCE'] || '2025-06-01'
      out_dir = options[:out_dir] || ENV['OUTPUT_DIR'] || 'data'

      collector = DevtoAnalytics::Collector.new(org: org, since: since, out_dir: out_dir)
      collector.run(write: true, format: options[:format])
    end

    desc 'list-articles', 'List articles for an organization (useful for discovering IDs)'
    option :org, type: :string, desc: 'Organization slug'
    option :since, type: :string, desc: 'ISO start date to filter articles'
    option :out_file, type: :string, desc: 'Optional file to write JSON list'
    def list_articles
      org = options[:org] || ENV['DEVTO_ORG_SLUG']
      raise Thor::RequiredArgumentMissingError, "No organization provided. Use --org or set DEVTO_ORG_SLUG." unless org
      since = options[:since] || ENV['DEVTO_SINCE'] || '2025-06-01'
      collector = DevtoAnalytics::Collector.new(org: org, since: since)
      articles = collector.list_articles

      if options[:out_file]
        File.write(options[:out_file], JSON.pretty_generate(articles))
        say "Wrote #{options[:out_file]}"
      else
        articles.each do |a|
          say "#{a['id']}  #{a['title']}  #{a['published_at']}  #{a['url'] || a['path']}"
        end
      end
    end
  end
end

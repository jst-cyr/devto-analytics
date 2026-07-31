# frozen_string_literal: true

require 'thor'

module DevtoAnalytics
  # Thor-based command-line entry points for fetching and inspecting analytics.
  class CLI < Thor
    desc 'fetch', 'Fetch analytics for an organization (delegates to Collector)'
    option :org, type: :string, desc: 'Organization slug (overrides DEVTO_ORG_SLUG)'
    option :since, type: :string, desc: 'ISO start date (overrides DEVTO_SINCE)'
    option :format, type: :string, default: 'csv', desc: 'Output format: csv or json'
    option :out_dir, type: :string, desc: 'Output directory (overrides OUTPUT_DIR)'
    option :days, type: :numeric, default: DevtoAnalytics::WeeklyCollector::DEFAULT_DAYS,
                  desc: 'Length of the recent-window CSV in whole UTC days, ending today'
    option :skip_window, type: :boolean, default: false,
                         desc: 'Skip the recent-window CSV (saves one API call per article)'
    def fetch
      org, since = org_and_since
      out_dir = options[:out_dir] || ENV['OUTPUT_DIR'] || 'data'

      collector = DevtoAnalytics::Collector.new(org: org, since: since, out_dir: out_dir)
      collector.run(write: true, format: options[:format],
                    weekly: !options[:skip_window], weekly_days: options[:days])
    end

    desc 'list-articles', 'List articles for an organization (useful for discovering IDs)'
    option :org, type: :string, desc: 'Organization slug'
    option :since, type: :string, desc: 'ISO start date to filter articles'
    option :out_file, type: :string, desc: 'Optional file to write JSON list'
    def list_articles
      org, since = org_and_since
      articles = DevtoAnalytics::Collector.new(org: org, since: since).all_articles

      if options[:out_file]
        File.write(options[:out_file], JSON.pretty_generate(articles))
        say "Wrote #{options[:out_file]}"
      else
        print_articles(articles)
      end
    end

    desc 'visualize', 'Start a local web server to visualize the analytics data'
    def visualize
      require_relative 'server'
      puts 'Starting visualization server at http://localhost:4567...'
      DevtoAnalytics::Server.run!
    end

    private

    def org_and_since
      org = options[:org] || ENV.fetch('DEVTO_ORG_SLUG', nil)
      raise Thor::RequiredArgumentMissingError, 'No organization provided. Use --org or set DEVTO_ORG_SLUG.' unless org

      [org, options[:since] || ENV['DEVTO_SINCE'] || '2025-06-01']
    end

    def print_articles(articles)
      articles.each do |a|
        say "#{a['id']}  #{a['title']}  #{a['published_at']}  #{a['url'] || a['path']}"
      end
    end
  end
end

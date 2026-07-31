# frozen_string_literal: true

require 'csv'

module DevtoAnalytics
  # Writes collected article rows/records out to CSV and JSON files.
  class Formatter
    TOTALS_HEADERS = %w[id title url published_at readers reactions comments].freeze

    WEEKLY_HEADERS = %w[
      id title url published_at window_start window_end
      readers read_time_seconds reactions comments follows
    ].freeze

    # Lifetime totals, one row per article.
    def self.write_csv(path, rows)
      write_rows(path, TOTALS_HEADERS, rows)
    end

    # Activity inside a fixed calendar-day window, one row per article.
    def self.write_weekly_csv(path, rows)
      write_rows(path, WEEKLY_HEADERS, rows)
    end

    def self.write_rows(path, headers, rows)
      CSV.open(path, 'w', write_headers: true, headers: headers) do |csv|
        rows.each { |row| csv << headers.map { |header| row[header] } }
      end
    end

    def self.write_json(path, obj)
      File.write(path, JSON.pretty_generate(obj))
    end
  end
end

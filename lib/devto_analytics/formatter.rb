# frozen_string_literal: true

require 'csv'
require 'time'

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
        sort_by_published_at(rows).each { |row| csv << headers.map { |header| row[header] } }
      end
    end

    # Oldest article first, newest last — the order it's handiest to review in.
    # Rows with a missing/unparseable published_at sort to the end.
    def self.sort_by_published_at(rows)
      rows.sort_by { |row| parse_published_at(row['published_at']) || Time.at(1 << 62) }
    end

    def self.parse_published_at(value)
      value && Time.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def self.write_json(path, obj)
      File.write(path, JSON.pretty_generate(obj))
    end
  end
end

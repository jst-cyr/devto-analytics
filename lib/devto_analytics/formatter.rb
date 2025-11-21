require 'csv'

module DevtoAnalytics
  class Formatter
    def self.write_csv(path, rows)
      CSV.open(path, 'w', write_headers: true, headers: %w[id url published_at]) do |csv|
        rows.each do |r|
          csv << [r['id'], r['url'], r['published_at']]
        end
      end
    end

    def self.write_json(path, obj)
      File.write(path, JSON.pretty_generate(obj))
    end
  end
end

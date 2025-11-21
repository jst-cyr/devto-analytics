require 'csv'

module DevtoAnalytics
  class Formatter
    def self.write_csv(path, rows)
      headers = %w[id title url published_at readers reactions comments]
      CSV.open(path, 'w', write_headers: true, headers: headers) do |csv|
        rows.each do |r|
          csv << [r['id'], r['title'], r['url'], r['published_at'], r['readers'], r['reactions'], r['comments']]
        end
      end
    end

    def self.write_json(path, obj)
      File.write(path, JSON.pretty_generate(obj))
    end
  end
end

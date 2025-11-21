require 'faraday'
require 'json'

module DevtoAnalytics
  class APIClient
    BASE_URL = 'https://dev.to'.freeze

    def initialize(api_key: ENV['DEVTO_API_KEY'])
      @api_key = api_key
      @conn = Faraday.new(url: BASE_URL) do |f|
        f.request :url_encoded
        f.response :raise_error
        f.adapter Faraday.default_adapter
      end
    end

    def list_articles(org_slug, per_page: 100, page: 1)
      # Prefer the organization-specific endpoint if available, falling back
      # to the `?username=` query. Both support `page` and `per_page` params.
      params = { per_page: per_page, page: page }
      headers = default_headers

      # Try org endpoint first
      begin
        org_path = "/api/organizations/#{org_slug}/articles"
        resp = @conn.get(org_path, params, headers)
        return parse_response(resp)
      rescue Faraday::ClientError => _e
        # fallback to username-based endpoint
      end

      begin
        path = "/api/articles"
        resp = @conn.get(path, params.merge(username: org_slug), headers)
        parse_response(resp)
      rescue Faraday::Error => e
        warn "API list_articles error: #{e.message}"
        []
      end
    end

    def get_article(article_id)
      resp = @conn.get("/api/articles/#{article_id}", {}, default_headers)
      parse_response(resp)
    rescue Faraday::Error => e
      warn "API get_article error: #{e.message}"
      nil
    end

    def analytics_totals(article_id)
      resp = @conn.get('/api/analytics/totals', { article_id: article_id }, default_headers)
      parse_response(resp)
    rescue Faraday::Error => e
      warn "API analytics_totals error: #{e.message}"
      nil
    end

    def analytics_historical(article_id, since: nil)
      params = { article_id: article_id }
      params[:start] = since if since
      resp = @conn.get('/api/analytics/historical', params, default_headers)
      parse_response(resp)
    rescue Faraday::Error => e
      warn "API analytics_historical error: #{e.message}"
      []
    end

    private

    def default_headers
      hdr = { 'api-key' => @api_key }
      hdr['Accept'] = ENV['DEVTO_ACCEPT_HEADER'] if ENV['DEVTO_ACCEPT_HEADER']
      hdr
    end

    def parse_response(resp)
      return nil unless resp && resp.body
      JSON.parse(resp.body)
    rescue JSON::ParserError
      resp.body
    end
  end
end

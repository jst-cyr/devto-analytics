require 'faraday'
require 'json'

module DevtoAnalytics
  class APIClient
    BASE_URL = 'https://dev.to'.freeze

    DEFAULT_MAX_RETRIES = 4
    DEFAULT_INITIAL_BACKOFF = 1 # seconds

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
      safe_get('/api/analytics/totals', { article_id: article_id }, default_headers)
    end

    def analytics_historical(article_id, since: nil)
      params = { article_id: article_id }
      params[:start] = since if since
      safe_get('/api/analytics/historical', params, default_headers)
    end

    private

    # Perform a GET with simple retry/backoff for 429 responses.
    def safe_get(path, params = {}, headers = {}, max_retries: DEFAULT_MAX_RETRIES, initial_backoff: DEFAULT_INITIAL_BACKOFF)
      retries = 0
      backoff = initial_backoff
      begin
        resp = @conn.get(path, params, headers)
        return parse_response(resp)
      rescue Faraday::ClientError => e
        status = nil
        begin
          status = e.response[:status] if e.respond_to?(:response) && e.response.is_a?(Hash)
        rescue StandardError
          status = nil
        end

        if status == 429 && retries < max_retries
          warn "Rate limited (429) on #{path}; retrying in #{backoff}s (attempt #{retries + 1}/#{max_retries})"
          sleep(backoff)
          retries += 1
          backoff *= 2
          retry
        end

        warn "API request error: #{e.message}"
        return nil
      rescue Faraday::Error => e
        warn "API request error: #{e.message}"
        return nil
      end
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

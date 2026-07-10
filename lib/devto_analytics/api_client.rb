# frozen_string_literal: true

require 'faraday'
require 'json'

module DevtoAnalytics
  # Thin wrapper around the dev.to / Forem REST API used by Collector.
  class APIClient
    BASE_URL = 'https://dev.to'

    DEFAULT_MAX_RETRIES = 4
    DEFAULT_INITIAL_BACKOFF = 1 # seconds

    def initialize(api_key: ENV.fetch('DEVTO_API_KEY', nil))
      @api_key = api_key
      @conn = Faraday.new(url: BASE_URL) do |f|
        f.request :url_encoded
        f.response :raise_error
        f.adapter Faraday.default_adapter
      end
    end

    # Prefers the organization-specific endpoint, falling back to the
    # `?username=` query if it's unavailable. Both support `page`/`per_page`.
    def list_articles(org_slug, per_page: 100, page: 1)
      params = { per_page: per_page, page: page }
      headers = default_headers

      org_articles = fetch_org_articles(org_slug, params, headers)
      return org_articles if org_articles

      fetch_user_articles(org_slug, params, headers)
    end

    def get_article(article_id)
      resp = @conn.get("/api/articles/#{article_id}", {}, default_headers)
      parse_response(resp)
    rescue Faraday::Error => e
      warn "API get_article error: #{e.message}"
      nil
    end

    def get_organization(org_slug)
      safe_get("/api/organizations/#{org_slug}", {}, default_headers)
    end

    # `organization_id` is required to retrieve analytics for articles authored
    # by other members of the org (Forem scopes per-article analytics to either
    # the API key's user or, when supplied, the organization).
    def analytics_totals(article_id, organization_id: nil)
      params = { article_id: article_id }
      params[:organization_id] = organization_id if organization_id
      safe_get('/api/analytics/totals', params, default_headers)
    end

    def analytics_historical(article_id, since: nil, organization_id: nil)
      params = { article_id: article_id }
      params[:start] = since if since
      params[:organization_id] = organization_id if organization_id
      safe_get('/api/analytics/historical', params, default_headers)
    end

    private

    def fetch_org_articles(org_slug, params, headers)
      resp = @conn.get("/api/organizations/#{org_slug}/articles", params, headers)
      parse_response(resp)
    rescue Faraday::ClientError
      nil
    end

    def fetch_user_articles(org_slug, params, headers)
      resp = @conn.get('/api/articles', params.merge(username: org_slug), headers)
      parse_response(resp)
    rescue Faraday::Error => e
      warn "API list_articles error: #{e.message}"
      []
    end

    # Perform a GET with simple retry/backoff for 429 responses.
    def safe_get(path, params = {}, headers = {}, max_retries: DEFAULT_MAX_RETRIES,
                 initial_backoff: DEFAULT_INITIAL_BACKOFF)
      retries = 0
      backoff = initial_backoff
      begin
        resp = @conn.get(path, params, headers)
        parse_response(resp)
      rescue Faraday::ClientError => e
        if client_error_status(e) == 429 && retries < max_retries
          warn "Rate limited (429) on #{path}; retrying in #{backoff}s (attempt #{retries + 1}/#{max_retries})"
          sleep(backoff)
          retries += 1
          backoff *= 2
          retry
        end

        warn "API request error: #{e.message}"
        nil
      rescue Faraday::Error => e
        warn "API request error: #{e.message}"
        nil
      end
    end

    def client_error_status(error)
      error.response[:status] if error.respond_to?(:response) && error.response.is_a?(Hash)
    rescue StandardError
      nil
    end

    def default_headers
      hdr = { 'api-key' => @api_key }
      hdr['Accept'] = ENV['DEVTO_ACCEPT_HEADER'] if ENV['DEVTO_ACCEPT_HEADER']
      hdr
    end

    def parse_response(resp)
      return nil unless resp&.body

      JSON.parse(resp.body)
    rescue JSON::ParserError
      resp.body
    end
  end
end

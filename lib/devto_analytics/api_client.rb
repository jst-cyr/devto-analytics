# frozen_string_literal: true

require 'faraday'
require 'json'

module DevtoAnalytics
  # Thin wrapper around the dev.to / Forem REST API used by Collector.
  class APIClient
    BASE_URL = 'https://dev.to'

    DEFAULT_MAX_RETRIES = (ENV['DEVTO_MAX_RETRIES'] || 6).to_i
    DEFAULT_INITIAL_BACKOFF = (ENV['DEVTO_INITIAL_BACKOFF'] || 2).to_i # seconds, used when no Retry-After header

    # Forem throttles API reads to ~3 req/s per key (Rack::Attack); pacing requests
    # below that rate avoids triggering 429s in the first place, rather than just
    # reacting to them after the fact.
    MIN_REQUEST_INTERVAL = (ENV['DEVTO_MIN_REQUEST_INTERVAL'] || 0.5).to_f # seconds

    def initialize(api_key: ENV.fetch('DEVTO_API_KEY', nil))
      @api_key = api_key
      @last_request_at = nil
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
      resp = paced_get("/api/articles/#{article_id}", {}, default_headers)
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
      resp = paced_get("/api/organizations/#{org_slug}/articles", params, headers)
      parse_response(resp)
    rescue Faraday::ClientError
      nil
    end

    def fetch_user_articles(org_slug, params, headers)
      resp = paced_get('/api/articles', params.merge(username: org_slug), headers)
      parse_response(resp)
    rescue Faraday::Error => e
      warn "API list_articles error: #{e.message}"
      []
    end

    # Perform a GET with retry/backoff for 429 responses. Waits at least as
    # long as the server's Retry-After header, but never less than our own
    # growing backoff — a short Retry-After hint isn't always long enough to
    # clear sustained throttling, and retrying too eagerly on it just refeeds
    # whatever counter is throttling us.
    def safe_get(path, params = {}, headers = {}, max_retries: DEFAULT_MAX_RETRIES,
                 initial_backoff: DEFAULT_INITIAL_BACKOFF)
      retries = 0
      backoff = initial_backoff
      begin
        resp = paced_get(path, params, headers)
        parse_response(resp)
      rescue Faraday::TooManyRequestsError => e
        if retries < max_retries
          wait = [retry_after_seconds(e), backoff].compact.max
          warn "Rate limited (429) on #{path}; retrying in #{wait}s (attempt #{retries + 1}/#{max_retries})"
          sleep(wait)
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

    # Paces requests to stay under Forem's per-key read throttle, sleeping
    # just enough since the last request rather than firing back-to-back.
    def paced_get(path, params, headers)
      if @last_request_at
        wait = MIN_REQUEST_INTERVAL - (monotonic_now - @last_request_at)
        sleep(wait) if wait.positive?
      end

      @conn.get(path, params, headers)
    ensure
      @last_request_at = monotonic_now
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def retry_after_seconds(error)
      value = error.response_headers && error.response_headers['Retry-After']
      Float(value) if value
    rescue ArgumentError, TypeError
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

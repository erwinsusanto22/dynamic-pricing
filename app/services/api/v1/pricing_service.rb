module Api::V1
  class PricingService < BaseService
    CACHE_TTL          = 5.minutes
    RACE_CONDITION_TTL = 10.seconds
    API_TIMEOUT        = 2.seconds

    ERROR_RATE_NOT_FOUND   = "Rate not found".freeze
    ERROR_RATE_UNAVAILABLE = "Rate unavailable".freeze

    def initialize(period:, hotel:, room:)
      @period = period
      @hotel  = hotel
      @room   = room
    end

    # Fetches the rate from the Redis cache
    # If not found, fetches from the API and cache it
    # Returns the rate or nil if not found
    def run
      cache_hit = true

      # expires_in: Cache expiration time
      # race_condition_ttl: Race condition TTL to prevent cache stampede
      # skip_nil: Skip caching if the value is nil
      @result = Rails.cache.fetch(
        cache_key,
        expires_in: CACHE_TTL,
        race_condition_ttl: RACE_CONDITION_TTL,
        skip_nil: true
      ) do
        cache_hit = false
        log_info(event: "cache_miss")

        value = fetch_rate_from_api

        if value.present?
          log_info(event: "cache_set")
        else
          log_warn(event: "skip_caching_nil")
        end

        value
      end

      log_info(event: "cache_hit") if cache_hit && @result.present?

      if @result.blank? && errors.empty?
        errors << ERROR_RATE_UNAVAILABLE
      end
    end

    private

    def fetch_rate_from_api
      response = Timeout.timeout(API_TIMEOUT) do
        RateApiClient.get_rate(
          period: @period,
          hotel:  @hotel,
          room:   @room
        )
      end

      unless response.success?
        log_error(event: "api_failure")
        errors << ERROR_RATE_UNAVAILABLE
        return nil
      end

      parsed_rate = JSON.parse(response.body)
      found_rate = parsed_rate['rates']&.detect { |r| r['period'] == @period && r['hotel'] == @hotel && r['room'] == @room }&.dig('rate')

      unless found_rate.present?
        errors << ERROR_RATE_NOT_FOUND
        return nil
      end

      found_rate.to_i
    rescue Timeout::Error
      log_error(event: "api_timeout")
      errors << ERROR_RATE_UNAVAILABLE
      nil
    rescue JSON::ParserError
      log_error(event: "invalid_json")
      errors << ERROR_RATE_UNAVAILABLE
      nil
    rescue StandardError => e
      log_error(event: "unexpected_error", message: e.message)
      errors << ERROR_RATE_UNAVAILABLE
      nil
    end

    def cache_key
      "pricing_rate:#{@period}:#{@hotel}:#{@room}"
    end

    # Rails Logger
    def log_info(payload)
      Rails.logger.info(log_payload(payload))
    end

    def log_warn(payload)
      Rails.logger.warn(log_payload(payload))
    end

    def log_error(payload)
      Rails.logger.error(log_payload(payload))
    end

    def log_payload(extra = {})
      {
        service: self.class.name,
        cache_key: cache_key,
        period: @period,
        hotel: @hotel,
        room: @room
      }.merge(extra)
    end
  end
end

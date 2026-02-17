require "test_helper"

class Api::V1::PricingServiceTest < ActiveSupport::TestCase
  def setup
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    @period = "Summer"
    @hotel  = "FloatingPointResort"
    @room   = "SingletonRoom"

    @service = Api::V1::PricingService.new(
      period: @period,
      hotel:  @hotel,
      room:   @room
    )
  end

  def teardown
    Rails.cache.clear
  end

  def cache_key
    @service.send(:cache_key)
  end

  test "returns cached rate when available" do
    Rails.cache.write(cache_key, "15000", expires_in: 5.minutes)

    @service.run

    assert @service.valid?
    assert_equal "15000", @service.result
    assert_empty @service.errors
  end

  test "fetches fresh rate on cache miss and caches it" do
    mock_body = {
      "rates" => [
        { "period" => @period, "hotel" => @hotel, "room" => @room, "rate" => "15000" }
      ]
    }.to_json

    mock_response = OpenStruct.new(success?: true, body: mock_body)

    RateApiClient.stub(:get_rate, mock_response) do
      @service.run

      assert @service.valid?
      assert_equal 15000, @service.result
      assert_equal 15000, Rails.cache.read(cache_key)
    end
  end

  test "does not cache nil results" do
    mock_response = OpenStruct.new(success?: false, body: nil)

    RateApiClient.stub(:get_rate, mock_response) do
      @service.run

      assert_not @service.valid?
      assert_nil Rails.cache.read(cache_key)
      assert_includes @service.errors, "Rate unavailable"
    end
  end

  test "does not call API again when cached" do
    Rails.cache.write(cache_key, "15000", expires_in: 5.minutes)

    RateApiClient.stub(:get_rate, -> { flunk("API should not be called on cache hit") }) do
      @service.run
    end

    assert_equal 15000, @service.result
  end

  test "handles rate not found in API response" do
    mock_body = {
      "rates" => [
        { "period" => "Winter", "hotel" => "OtherHotel", "room" => "OtherRoom", "rate" => "99999" }
      ]
    }.to_json

    mock_response = OpenStruct.new(success?: true, body: mock_body)

    RateApiClient.stub(:get_rate, mock_response) do
      @service.run

      assert_not @service.valid?
      assert_nil @service.result
      assert_includes @service.errors, "Rate not found"
    end
  end

  test "handles API failure gracefully" do
    mock_response = OpenStruct.new(success?: false, body: nil)

    RateApiClient.stub(:get_rate, mock_response) do
      @service.run

      assert_not @service.valid?
      assert_nil @service.result
      assert_includes @service.errors, "Rate unavailable"
    end
  end

  test "handles API timeout" do
    RateApiClient.stub(:get_rate, ->(*) { raise Timeout::Error }) do
      @service.run

      assert_not @service.valid?
      assert_nil @service.result
      assert_includes @service.errors, "Rate unavailable"
    end
  end

  test "handles invalid JSON response" do
    mock_response = OpenStruct.new(success?: true, body: "invalid json")

    RateApiClient.stub(:get_rate, mock_response) do
      @service.run

      assert_not @service.valid?
      assert_nil @service.result
      assert_includes @service.errors, "Rate unavailable"
    end
  end

  test "generates correct cache key" do
    assert_equal(
      "pricing_rate:Summer:FloatingPointResort:SingletonRoom",
      cache_key
    )
  end

  test "logs cache hit and miss events" do
    mock_body = {
      "rates" => [
        { "period" => @period, "hotel" => @hotel, "room" => @room, "rate" => "15000" }
      ]
    }.to_json

    mock_response = OpenStruct.new(success?: true, body: mock_body)

    # ---- Cache MISS ----
    log_output = StringIO.new
    logger = Logger.new(log_output)

    Rails.stub(:logger, logger) do
      RateApiClient.stub(:get_rate, mock_response) do
        @service.run
      end
    end

    assert_includes log_output.string, "cache_miss"
    assert_includes log_output.string, "cache_set"

    # ---- Cache HIT ----
    Rails.cache.write(cache_key, "15000")

    log_output = StringIO.new
    logger = Logger.new(log_output)

    Rails.stub(:logger, logger) do
      @service.run
    end

    assert_includes log_output.string, "cache_hit"
  end
end

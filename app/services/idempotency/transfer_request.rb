require "digest"
require "json"

module Idempotency
  class TransferRequest
    Result = Data.define(:status, :body)
    class MissingKey < StandardError; end
    class Conflict < StandardError; end
    class InProgress < StandardError; end

    CLAIM_TIMEOUT = 30.seconds
    WAIT_TIMEOUT = 5.seconds
    POLL_INTERVAL = 0.05.seconds

    def self.call(key:, request_params:, &)
      new(key:, request_params:).call(&)
    end

    def initialize(key:, request_params:)
      @key = key.to_s
      @request_params = request_params
      @fingerprint = Digest::SHA256.hexdigest(JSON.generate(canonicalize(request_params)))
    end

    def call
      raise MissingKey, "Idempotency-Key header is required" if @key.blank?

      record, claimed = claim
      return replay(record) unless claimed

      status, body = yield
      response_status = Rack::Utils.status_code(status)
      record.update!(status: "completed", response_status:, response_body: body)
      Result.new(response_status, body)
    rescue StandardError
      record&.update_columns(status: "failed", updated_at: Time.current) if claimed && record.status == "in_progress"
      raise
    end

    private

    def claim
      record = IdempotencyKey.new(
        key: @key,
        request_fingerprint: @fingerprint,
        status: "in_progress"
      )
      record.save!(validate: false)
      [ record, true ]
    rescue ActiveRecord::RecordNotUnique
      wait_for_existing_claim
    end

    def wait_for_existing_claim
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_TIMEOUT

      loop do
        record = IdempotencyKey.find_by!(key: @key)
        raise Conflict, "Idempotency key was used with a different request" unless record.request_fingerprint == @fingerprint
        return [ record, false ] if record.status == "completed"
        return reclaim(record) if record.status == "failed" || stale?(record)
        raise InProgress, "A request with this Idempotency-Key is already in progress" if
          Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep POLL_INTERVAL
      end
    end

    def reclaim(record)
      IdempotencyKey.transaction do
        locked_record = IdempotencyKey.lock.find(record.id)
        if locked_record.status == "failed" || stale?(locked_record)
          locked_record.update!(status: "in_progress", updated_at: Time.current)
          return [ locked_record, true ]
        end
        [ locked_record, false ]
      end
    end

    def replay(record)
      raise InProgress, "A request with this Idempotency-Key is already in progress" unless record.status == "completed"

      Result.new(record.response_status, record.response_body)
    end

    def stale?(record)
      record.updated_at < CLAIM_TIMEOUT.ago
    end

    def canonicalize(value)
      case value
      when Hash
        value.stringify_keys.sort.to_h { |key, item| [ key, canonicalize(item) ] }
      when Array
        value.map { |item| canonicalize(item) }
      else
        value
      end
    end
  end
end

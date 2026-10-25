require "digest"
require "json"

module Idempotency
  # Claims, executes, and replays an idempotent transfer request.
  class TransferRequest
    Result = Data.define(:status, :body)
    class MissingKey < StandardError; end
    class Conflict < StandardError; end
    class InProgress < StandardError; end

    CLAIM_TIMEOUT = 30.seconds
    WAIT_TIMEOUT = 5.seconds
    POLL_INTERVAL = 0.05.seconds

    # Executes a transfer request once and replays its stored result on retries.
    #
    # @param key [String] required client-supplied idempotency key
    # @param request_params [Hash] parameters used to build the request fingerprint
    # @yieldreturn [Array] status and response body produced by the transfer
    # @return [Result] response status and body, either fresh or replayed
    # @raise [MissingKey] if key is blank
    # @raise [Conflict] if the key has a different request fingerprint
    # @raise [InProgress] if another request still owns the active claim
    def self.call(key:, request_params:, &)
      new(key:, request_params:).call(&)
    end

    # Stores the key and computes a stable fingerprint for the request payload.
    def initialize(key:, request_params:)
      @key = key.to_s
      @request_params = request_params
      @fingerprint = Digest::SHA256.hexdigest(JSON.generate(canonicalize(request_params)))
    end

    # Executes a claimed request and returns its stored result for later retries.
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

    # Attempts to create the unique in-progress record for this request.
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

    # Waits for, reclaims, or rejects an existing idempotency claim.
    def wait_for_existing_claim
      # Poll briefly so a concurrent request can finish before returning a
      # conflict, while still bounding how long this request waits.
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

    # Reclaims a failed or stale record while holding its database row lock.
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

    # Returns the stored response when the idempotent request is complete.
    def replay(record)
      raise InProgress, "A request with this Idempotency-Key is already in progress" unless record.status == "completed"

      Result.new(record.response_status, record.response_body)
    end

    # Checks whether a claim has exceeded the allowed claim timeout.
    def stale?(record)
      record.updated_at < CLAIM_TIMEOUT.ago
    end

    # Recursively sorts request hashes so equivalent payloads share a fingerprint.
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

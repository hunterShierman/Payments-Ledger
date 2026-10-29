require "base64"
require "json"

module CursorPagination
  extend ActiveSupport::Concern

  DEFAULT_PAGE_SIZE = 50
  MAX_PAGE_SIZE = 100

  private

  def paginate_relation(relation)
    limit = page_limit
    records = relation.order(created_at: :asc, id: :asc).limit(limit + 1)

    if (cursor = page_cursor)
      records = records.where("(created_at, id) > (?, ?)", cursor[:created_at], cursor[:id])
    end

    records = records.to_a
    has_more = records.length > limit
    records = records.first(limit) if has_more

    [ records, has_more ? encode_cursor(records.last) : nil ]
  end

  def page_limit
    value = params[:limit].presence || DEFAULT_PAGE_SIZE
    limit = Integer(value.to_s, 10)
    raise ArgumentError unless limit.between?(1, MAX_PAGE_SIZE)

    limit
  rescue ArgumentError, TypeError
    raise InvalidCursorPagination, "limit must be between 1 and #{MAX_PAGE_SIZE}"
  end

  def page_cursor
    return if params[:cursor].blank?

    decoded = JSON.parse(Base64.urlsafe_decode64(params[:cursor]))
    {
      created_at: Time.iso8601(decoded.fetch("created_at")),
      id: Integer(decoded.fetch("id").to_s, 10)
    }
  rescue ArgumentError, TypeError, KeyError, JSON::ParserError
    raise InvalidCursorPagination, "cursor is invalid"
  end

  def encode_cursor(record)
    Base64.urlsafe_encode64(
      { created_at: record.created_at.utc.iso8601(6), id: record.id }.to_json,
      padding: false
    )
  end

  class InvalidCursorPagination < StandardError
  end
end

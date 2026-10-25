class CreateIdempotencyKeys < ActiveRecord::Migration[8.1]
  # Creates unique request claims and storage for replayable responses.
  def change
    create_table :idempotency_keys do |t|
      t.string :key, null: false
      t.string :request_fingerprint, null: false
      t.string :status, null: false, default: "in_progress"
      t.integer :response_status
      t.jsonb :response_body
      t.timestamps
    end

    add_index :idempotency_keys, :key, unique: true
  end
end

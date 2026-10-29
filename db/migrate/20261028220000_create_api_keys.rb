class CreateApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :api_keys do |t|
      t.string :name
      t.string :key_digest, null: false
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :api_keys, :key_digest, unique: true
  end
end

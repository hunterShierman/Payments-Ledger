class CreateAccounts < ActiveRecord::Migration[8.1]
  # Creates accounts with a currency and transactionally maintained balance.
  def change
    create_table :accounts do |t|
      t.string :currency, null: false
      t.bigint :balance_cents, null: false, default: 0

      t.timestamps
    end
  end
end

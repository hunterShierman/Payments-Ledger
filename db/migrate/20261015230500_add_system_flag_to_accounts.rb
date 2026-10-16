class AddSystemFlagToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :system, :boolean, null: false, default: false
    add_index :accounts, :currency, unique: true, where: "system", name: "index_accounts_on_currency_for_system_accounts"
  end
end

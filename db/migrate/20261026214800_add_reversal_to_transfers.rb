class AddReversalToTransfers < ActiveRecord::Migration[8.0]
  def change
    add_reference :transfers, :reversal_of_transfer, foreign_key: { to_table: :transfers }, index: { unique: true }
  end
end

class EnforceLedgerEntriesAppendOnly < ActiveRecord::Migration[8.1]
  # Adds the trigger that prevents historical ledger entries from changing.
  def up
    # Historical entries are corrected with new reversal entries, never edits.
    # A database trigger protects this invariant even when SQL bypasses Rails.
    execute <<~SQL
      CREATE FUNCTION prevent_ledger_entries_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'ledger_entries is append-only';
      END;
      $$;

      CREATE TRIGGER ledger_entries_append_only
      BEFORE UPDATE OR DELETE ON ledger_entries
      FOR EACH ROW
      EXECUTE FUNCTION prevent_ledger_entries_mutation();
    SQL
  end

  # Removes the append-only trigger and function when rolling back the migration.
  def down
    execute <<~SQL
      DROP TRIGGER ledger_entries_append_only ON ledger_entries;
      DROP FUNCTION prevent_ledger_entries_mutation();
    SQL
  end
end

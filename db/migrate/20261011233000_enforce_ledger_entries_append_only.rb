class EnforceLedgerEntriesAppendOnly < ActiveRecord::Migration[8.1]
  def up
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

  def down
    execute <<~SQL
      DROP TRIGGER ledger_entries_append_only ON ledger_entries;
      DROP FUNCTION prevent_ledger_entries_mutation();
    SQL
  end
end

defmodule Inklinks.Repo.Migrations.CreateEvents do
  @moduledoc """
  The event log: one append-only table, written in SQL so it reads as the
  spec it is (see docs/events.md).

  The database, not just the code, guarantees that the log only grows:

    * a row trigger refuses UPDATE and DELETE;
    * a statement trigger refuses TRUNCATE;
    * PUBLIC loses those privileges. In production the app should connect
      as a role granted only SELECT and INSERT on this table. The owner and
      superusers keep their privileges, which is why the triggers matter:
      triggers bind them too.
  """
  use Ecto.Migration

  def up do
    execute """
    CREATE TABLE events (
      -- Global order. GENERATED ALWAYS: nobody chooses a position.
      position       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      id             uuid        NOT NULL UNIQUE,
      -- The stream is one reading; later, a reader's own stream too.
      stream_type    text        NOT NULL CHECK (stream_type IN ('reading', 'reader')),
      stream_id      uuid        NOT NULL,
      -- 1, 2, 3… within the stream. The unique constraint below is the
      -- optimistic lock: two writers expecting the same version collide.
      stream_version integer     NOT NULL CHECK (stream_version >= 1),
      type           text        NOT NULL CHECK (type ~ '^[a-z][a-z0-9_]*$'),
      type_version   smallint    NOT NULL DEFAULT 1 CHECK (type_version >= 1),
      data           jsonb       NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(data) = 'object'),
      -- Denormalized from the stream, for the Inker's queries.
      reader_id      uuid        NOT NULL,
      inklink_id     text,
      -- When it happened (server clock; inferred events use the inferred
      -- moment), and when it was written.
      occurred_at    timestamptz NOT NULL,
      recorded_at    timestamptz NOT NULL DEFAULT now(),
      UNIQUE (stream_id, stream_version)
    )
    """

    execute "CREATE INDEX events_reader_idx ON events (reader_id, position)"
    execute "CREATE INDEX events_inklink_type_idx ON events (inklink_id, type, position)"
    execute "CREATE INDEX events_data_idx ON events USING gin (data jsonb_path_ops)"

    execute """
    CREATE FUNCTION events_refuse_change() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'events is append-only: % refused', TG_OP
        USING ERRCODE = 'restrict_violation';
    END
    $$
    """

    execute """
    CREATE TRIGGER events_no_update_or_delete
      BEFORE UPDATE OR DELETE ON events
      FOR EACH ROW EXECUTE FUNCTION events_refuse_change()
    """

    execute """
    CREATE TRIGGER events_no_truncate
      BEFORE TRUNCATE ON events
      FOR EACH STATEMENT EXECUTE FUNCTION events_refuse_change()
    """

    execute "REVOKE UPDATE, DELETE, TRUNCATE ON events FROM PUBLIC"
  end

  def down do
    execute "DROP TABLE events"
    execute "DROP FUNCTION events_refuse_change()"
  end
end

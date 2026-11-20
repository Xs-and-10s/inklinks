defmodule Inklinks.Repo.Migrations.AddOriginToEvents do
  @moduledoc """
  Every event says where it came from: `linker`, `engine` or `platform`
  (see Inklinks.Events.Catalog).

  Adding a column with a default fills existing rows without an UPDATE, so
  the append-only trigger is not involved. Rows written before this
  migration read as `platform`; only development data predates it.
  """
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE events
      ADD COLUMN origin text NOT NULL DEFAULT 'platform'
      CHECK (origin IN ('linker', 'engine', 'platform'))
    """

    execute "CREATE INDEX events_origin_idx ON events (stream_id, stream_version) WHERE origin = 'linker'"
  end

  def down do
    execute "DROP INDEX events_origin_idx"
    execute "ALTER TABLE events DROP COLUMN origin"
  end
end

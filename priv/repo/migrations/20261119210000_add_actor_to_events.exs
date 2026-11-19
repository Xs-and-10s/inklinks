defmodule Inklinks.Repo.Migrations.AddActorToEvents do
  @moduledoc """
  Every event says who caused it: `linker`, `engine` or `platform`
  (see Inklinks.Events.Catalog).

  Adding a column with a default fills existing rows without an UPDATE, so
  the append-only trigger is not involved. Rows written before this
  migration read as `platform`; only development data predates it.
  """
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE events
      ADD COLUMN actor text NOT NULL DEFAULT 'platform'
      CHECK (actor IN ('linker', 'engine', 'platform'))
    """

    execute "CREATE INDEX events_actor_idx ON events (stream_id, stream_version) WHERE actor = 'linker'"
  end

  def down do
    execute "DROP INDEX events_actor_idx"
    execute "ALTER TABLE events DROP COLUMN actor"
  end
end

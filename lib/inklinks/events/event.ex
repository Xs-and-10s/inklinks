defmodule Inklinks.Events.Event do
  @moduledoc """
  One row of the event log, as read back. See docs/events.md.

  Events are only ever inserted (by `Inklinks.Events.append/3`), so this
  schema has no changeset: nothing here can update a row, and the database
  would refuse if anything tried.
  """
  use Ecto.Schema

  @primary_key {:position, :id, autogenerate: true}
  schema "events" do
    field :id, Ecto.UUID
    field :stream_type, :string
    field :stream_id, Ecto.UUID
    field :stream_version, :integer
    field :type, :string
    field :type_version, :integer, default: 1
    field :origin, :string, default: "platform"
    field :data, :map, default: %{}
    field :reader_id, Ecto.UUID
    field :inklink_id, :string
    field :occurred_at, :utc_datetime_usec
    field :recorded_at, :utc_datetime_usec, read_after_writes: true
  end

  @type t :: %__MODULE__{
          position: pos_integer(),
          id: Ecto.UUID.t(),
          stream_type: String.t(),
          stream_id: Ecto.UUID.t(),
          stream_version: pos_integer(),
          type: String.t(),
          type_version: pos_integer(),
          origin: String.t(),
          data: map(),
          reader_id: Ecto.UUID.t(),
          inklink_id: String.t() | nil,
          occurred_at: DateTime.t(),
          recorded_at: DateTime.t()
        }
end

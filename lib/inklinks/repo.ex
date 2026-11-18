defmodule Inklinks.Repo do
  use Ecto.Repo,
    otp_app: :inklinks,
    adapter: Ecto.Adapters.Postgres
end

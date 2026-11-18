defmodule InklinksWeb.LibraryHTML do
  use InklinksWeb, :html

  embed_templates "library_html/*"

  @doc "A setting as a reader would say it: `story-game` stays, nil is a dash."
  def describe(nil), do: "—"
  def describe(value), do: value
end

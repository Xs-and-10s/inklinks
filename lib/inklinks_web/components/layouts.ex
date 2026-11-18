defmodule InklinksWeb.Layouts do
  @moduledoc """
  The root layout, and the `app/1` frame every page sits in.

  The markup is semantic on purpose: the stylesheet styles `header`, `nav`,
  `main` and ARIA state, not class names.
  """
  use InklinksWeb, :html

  embed_templates "layouts/*"

  @doc "The site frame: a banner with the site's name, then the page."
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header>
      <nav aria-label="Site">
        <a href={~p"/"} rel="home">Inklinks</a>
      </nav>
    </header>
    <main>
      {render_slot(@inner_block)}
    </main>
    """
  end
end

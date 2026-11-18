defmodule Inklinks.Engine.Stub.World do
  @moduledoc """
  The stub's state of one reading, and the expressions that read it.

  `vals` holds facts by key (`"skittles.grievance"`), `lists` holds lists
  of entries, `aka` holds each NPC's shuffled bag of other names, and `rng`
  is a xorshift64 generator, the same one the Rust interpreter uses, so the
  same seed shuffles the same way in both.

  A value is a number, a boolean, text (a string), `nil`, a list, or a name
  (`{:id, "chin"}`): names are what bare words in the IR are.
  """

  alias Inklinks.Engine.Stub.Story

  defstruct at: nil, vals: %{}, lists: %{}, aka: %{}, visits: %{}, rng: 1, view: nil, offered: []

  @type value :: number() | boolean() | String.t() | nil | [value()] | {:id, String.t()}
  @type t :: %__MODULE__{}

  @mask 0xFFFF_FFFF_FFFF_FFFF

  @doc "A new world: declared facts and lists, and the dice seeded."
  @spec new(Story.t(), integer()) :: t()
  def new(%Story{} = story, seed) do
    world = %__MODULE__{rng: max(band(seed), 1)}

    Enum.reduce(Map.values(story.declared), world, fn
      %{"declare" => "fact"} = fact, w ->
        {value, w} = eval(fact["value"], story, w)
        put_in(w.vals[fact_key(fact)], value)

      %{"declare" => "list", "id" => id} = list, w ->
        put_in(w.lists[id], Enum.map(list["holds"] || [], &entry/1))

      _, w ->
        w
    end)
  end

  defp fact_key(%{"id" => id, "belongs_to" => owner}) when is_binary(owner), do: "#{owner}.#{id}"
  defp fact_key(%{"id" => id}), do: id

  defp entry(holds),
    do: %{id: holds["id"], label: holds["label"], mark: holds["mark"], struck: false}

  # -- expressions ---------------------------------------------------------------

  @doc "Evaluates an IR expression. Returns the world too: reading `aka` rolls dice."
  @spec eval(term(), Story.t(), t()) :: {value(), t()}
  def eval(nil, _story, w), do: {nil, w}
  def eval(value, _story, w) when is_number(value) or is_boolean(value), do: {value, w}
  def eval("me", story, w), do: {{:id, story.pov}, w}

  def eval(name, _story, w) when is_binary(name) do
    case Map.fetch(w.vals, name) do
      {:ok, value} -> {value, w}
      :error -> {{:id, name}, w}
    end
  end

  def eval(%{"str" => text}, _story, w), do: {text, w}
  def eval(%{"get" => [subject, field]}, story, w), do: get(subject, field, story, w)

  def eval(%{"not" => a}, story, w) do
    {v, w} = eval(a, story, w)
    {not truthy?(v), w}
  end

  def eval(%{"neg" => a}, story, w) do
    {v, w} = eval(a, story, w)
    {-v, w}
  end

  def eval(%{"and" => args}, story, w) do
    Enum.reduce_while(args, {true, w}, fn arg, {_, w} ->
      {v, w} = eval(arg, story, w)
      if truthy?(v), do: {:cont, {true, w}}, else: {:halt, {false, w}}
    end)
  end

  def eval(%{"or" => args}, story, w) do
    Enum.reduce_while(args, {false, w}, fn arg, {_, w} ->
      {v, w} = eval(arg, story, w)
      if truthy?(v), do: {:halt, {true, w}}, else: {:cont, {false, w}}
    end)
  end

  def eval(%{} = expr, story, w) when map_size(expr) == 1 do
    [{op, [a, b]}] = Map.to_list(expr)
    {a, w} = eval(a, story, w)
    {b, w} = eval(b, story, w)
    {binary(op, a, b), w}
  end

  defp binary("==", a, b), do: a == b
  defp binary("!=", a, b), do: a != b
  defp binary("<", a, b), do: a < b
  defp binary(">", a, b), do: a > b
  defp binary("<=", a, b), do: a <= b
  defp binary(">=", a, b), do: a >= b
  defp binary("+", a, b), do: a + b
  defp binary("-", a, b), do: a - b
  defp binary("*", a, b), do: a * b
  defp binary("/", a, b), do: a / b
  defp binary("mod", a, b), do: rem(a, b)

  @doc "Whether a value counts as true: anything but false, nil, 0 and empty."
  def truthy?(v), do: v not in [false, nil, 0, "", []]

  defp get(subject, field, story, w) do
    {subject, w} = eval(subject, story, w)
    id = name(subject)

    cond do
      field == "aka" -> aka(id, story, w)
      field == "count" and Map.has_key?(w.lists, id) -> {length(w.lists[id]), w}
      field in ["name", "label"] -> {label(id, story, w), w}
      Map.has_key?(w.vals, "#{id}.#{field}") -> {w.vals["#{id}.#{field}"], w}
      true -> {constant(story.declared[id][field]), w}
    end
  end

  defp constant(nil), do: nil
  defp constant(v) when is_binary(v), do: {:id, v}
  defp constant(v), do: v

  @doc "The key a `set` target writes: `me.treat` is `skittles.treat`."
  def key(%{"get" => [subject, field]}, story, w) do
    {subject, _} = eval(subject, story, w)
    "#{name(subject)}.#{field}"
  end

  def key(name, _story, _w) when is_binary(name), do: name

  defp name({:id, id}), do: id
  defp name(other), do: to_string(other)

  @doc "A thing's name as readers see it."
  def label(id, story, w) do
    w.vals["#{id}.name"] || get_in(story.declared, [id, "label"]) || id
  end

  @doc "How a value reads in the story."
  def show({:id, id}, story, w), do: label(id, story, w)
  def show(nil, _story, _w), do: ""
  def show(n, _story, _w) when is_float(n) and n == trunc(n), do: Integer.to_string(trunc(n))
  def show(list, story, w) when is_list(list), do: Enum.map_join(list, ", ", &show(&1, story, w))
  def show(v, _story, _w), do: to_string(v)

  # The next of an NPC's other names, as the Rust interpreter picks them: a
  # bag in the declared order (`aka_order`), shuffled by default, refilled
  # when it runs out.
  defp aka(id, story, w) do
    names = get_in(story.declared, [id, "aka"]) || []
    order = get_in(story.declared, [id, "aka_order"]) || "shuffled"
    n = length(names)

    cond do
      n == 0 ->
        {label(id, story, w), w}

      order == "random" ->
        {roll, w} = roll(w, n)
        {Enum.at(names, roll - 1), w}

      true ->
        {bag, used} = Map.get(w.aka, id, {[], 0})

        {bag, used, w} =
          if bag == [] or used == n, do: refill(n, order, w), else: {bag, used, w}

        w = put_in(w.aka[id], {bag, used + 1})
        {Enum.at(names, Enum.at(bag, used)), w}
    end
  end

  defp refill(n, "in order", w), do: {Enum.to_list(0..(n - 1)), 0, w}
  defp refill(n, "reversed", w), do: {Enum.to_list((n - 1)..0//-1), 0, w}

  defp refill(n, _shuffled, w) do
    # Fisher–Yates from the top, as the Rust interpreter does.
    {bag, w} =
      Enum.reduce((n - 1)..1//-1, {List.to_tuple(Enum.to_list(0..(n - 1))), w}, fn i, {bag, w} ->
        {roll, w} = roll(w, i + 1)
        j = roll - 1
        {bag |> put_elem(i, elem(bag, j)) |> put_elem(j, elem(bag, i)), w}
      end)

    {Tuple.to_list(bag), 0, w}
  end

  @doc "Rolls 1..sides with xorshift64."
  def roll(%__MODULE__{rng: x} = w, sides) do
    import Bitwise
    x = bxor(x, x <<< 13 &&& @mask)
    x = bxor(x, x >>> 7)
    x = bxor(x, x <<< 17 &&& @mask)
    {1 + rem(x, max(sides, 1)), %{w | rng: x}}
  end

  defp band(seed), do: Bitwise.band(seed, @mask)
end

defmodule Saner.Walkers.FunctionDefinitions do
  alias Saner.Structs.Mfa
  alias Saner.Structs.Location

  defmodule State do
    @type t :: %__MODULE__{
            module_stack: [[atom()]],
            hits: %{{module(), atom(), integer()} => Location.t()}
          }

    defstruct module_stack: [],
              hits: %{}

    def new() do
      %__MODULE__{}
    end

    def push_modules(state, modules) when is_list(modules) do
      %__MODULE__{state | module_stack: [modules | state.module_stack]}
    end

    def pop_modules(%__MODULE__{module_stack: [_ | tail]} = state) do
      %__MODULE__{state | module_stack: tail}
    end

    def cur_module(%__MODULE__{module_stack: module_stack}) do
      module_stack
      |> Enum.reverse()
      |> Enum.flat_map(& &1)
      |> Module.concat()
    end

    def add_hit(state, fun, arities, location) when is_list(arities) do
      arities
      |> Enum.reduce(state, fn a, state -> add_hit(state, fun, a, location) end)
    end

    def add_hit(%__MODULE__{hits: hits} = state, fun, arity, location)
        when is_atom(fun) and is_integer(arity) do
      mod = State.cur_module(state)
      hits = Map.put_new(hits, {mod, fun, arity}, location)
      %__MODULE__{state | hits: hits}
    end
  end

  @spec extract(ast :: term) :: [{Mfa.t(), Location.t()}]
  def extract(ast) do
    {_new_ast, state} = Macro.traverse(ast, State.new(), &pre_visit/2, &post_visit/2)
    Enum.reverse(state.hits)
  end

  def pre_visit(node, acc), do: visit(node, acc, :pre)
  def post_visit(node, acc), do: visit(node, acc, :post)

  def visit({:defmodule, _meta, [{:__aliases__, _, module_parts} | _]} = ast, state, stage) do
    # IO.inspect state.module_stack, label: :stack
    case stage do
      :pre ->
        {ast, State.push_modules(state, module_parts)}

      :post ->
        {ast, State.pop_modules(state)}
    end
  end

  def visit({:def, meta, [{:when, _, [function_head | _guards]}, body]}, state, stage) do
    visit({:def, meta, [function_head, body]}, state, stage)
  end

  def visit({:def, meta, [{function_name, _, args} | _]} = ast, state, :pre) do
    arities = arg_counts(args)
    state = State.add_hit(state, function_name, arities, Location.from_meta(meta))

    {ast, state}
  end

  def visit({:def, _, _} = _ast, _state, :pre) do
    raise "missed def"
    # {ast, state}
  end

  def visit(node, acc, stage) do
    _node = node
    _stage = stage
    # IO.inspect(node)
    # IO.inspect(stage)
    # IO.puts "NOP"
    {node, acc}
  end

  defp arg_counts(args) when is_list(args) do
    {min, max} =
      Enum.reduce(args, {0, 0}, fn
        {:\\, _meta, _}, {min, max} ->
          {min, max + 1}

        _, {min, max} ->
          {min + 1, max + 1}
      end)

    Enum.to_list(min..max)
  end
end

defmodule Admin.Components.EvalSelector do
  @moduledoc """
  A reusable component for selecting AI evaluations.

  This component provides a consistent interface for evaluation selection
  across different AI-related pages in the application.
  """
  use Phoenix.Component

  @doc """
  Renders an evaluation selector dropdown.

  ## Examples

      <.eval_selector
        available_evals={@evals}
        selected_eval={@selected_eval}
        on_change="eval_changed"
        class="w-[200px]"
      />
  """
  attr :available_evals, :list, required: true, doc: "List of available evaluations"
  attr :selected_eval, :string, required: true, doc: "Currently selected evaluation name"
  attr :on_change, :string, required: true, doc: "Phoenix event to trigger on evaluation change"
  attr :class, :string, default: "w-[200px]", doc: "CSS classes for the select trigger"
  attr :id, :string, default: "eval-select", doc: "HTML ID for the select element"
  attr :show_default, :boolean, default: true, doc: "Whether to show 'No Eval Selected' option"
  attr :show_all_option, :boolean, default: false, doc: "Whether to show 'All Evaluations' option"

  attr :all_option_text, :string,
    default: "All Evaluations",
    doc: "Text for all evaluations option"

  attr :all_option_value, :string, default: "all", doc: "Value for all evaluations option"
  attr :key, :string, default: nil, doc: "Optional key for forcing re-render"

  def eval_selector(assigns) do
    ~H"""
    <form phx-change={@on_change}>
      <select id={@id} name="eval" class={["select select-bordered", @class]} key={@key}>
        <%= if @show_all_option do %>
          <option value={@all_option_value} selected={@selected_eval == @all_option_value}>
            {@all_option_text}
          </option>
        <% end %>
        <%= if @show_default do %>
          <option value="No Eval Selected" selected={@selected_eval == "No Eval Selected"}>
            No Eval Selected
          </option>
        <% end %>
        <%= for eval <- @available_evals do %>
          <option value={eval.name} selected={@selected_eval == eval.name}>
            {String.slice(eval.name, 0, 20)}{if String.length(eval.name) > 20, do: "..."}
          </option>
        <% end %>
      </select>
    </form>
    """
  end
end

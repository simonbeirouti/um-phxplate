defmodule Admin.Components.ModelSelector do
  @moduledoc """
  A reusable component for selecting AI models.

  This component provides a consistent interface for model selection
  across different AI-related pages in the application.
  """
  use Phoenix.Component
  alias Core.AI.Models

  @doc """
  Renders a model selector dropdown.

  ## Examples

      <.model_selector
        selected_model={@selected_model}
        on_change="select_model"
        class="w-[140px]"
      />
  """
  attr :selected_model, :string, required: true, doc: "Currently selected model display name"
  attr :on_change, :string, required: true, doc: "Phoenix event to trigger on model change"
  attr :class, :string, default: "w-[200px]", doc: "CSS classes for the select trigger"
  attr :id, :string, default: "model-select", doc: "HTML ID for the select element"
  attr :include_all_option, :boolean, default: false, doc: "Whether to include 'All Models' option"

  attr :side, :string,
    values: ~w(top bottom),
    default: "bottom",
    doc: "The side where the select content opens"

  def model_selector(assigns) do
    assigns = assign(assigns, :available_models, Models.available_models())

    ~H"""
    <form phx-change={@on_change}>
      <select id={@id} name="model" class={["select select-bordered", @class]}>
        <%= if @include_all_option do %>
          <option value="All Models" selected={@selected_model == "All Models"}>
            All Models
          </option>
        <% end %>
        <%= for {name, _api_id} <- @available_models do %>
          <option value={name} selected={@selected_model == name}>{name}</option>
        <% end %>
      </select>
    </form>
    """
  end
end

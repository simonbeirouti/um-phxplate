defmodule Admin.Components.EvaluationQueue do
  @moduledoc """
  Component for displaying the evaluation queue status in an accordion format.
  """
  use Phoenix.Component

  attr :queue_status, :map, required: true
  attr :class, :string, default: nil

  def evaluation_queue_accordion(assigns) do
    ~H"""
    <div class={["mt-4 mb-6", @class]}>
      <div class="collapse collapse-arrow bg-base-100 shadow">
        <input type="checkbox" id="evaluation-queue-accordion" />
        <label for="evaluation-queue-accordion" class="collapse-title text-lg font-medium">
          Evaluation Queue
        </label>
        <div class="collapse-content">
          <div class="grid grid-cols-2 gap-4">
            <div class="bg-info/10 text-info-content overflow-hidden shadow rounded-lg">
              <div class="p-4">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <div class="w-8 h-8 bg-info rounded-md flex items-center justify-center">
                      <span class="text-info-content font-bold text-sm">
                        <%= @queue_status.queue_size %>
                      </span>
                    </div>
                  </div>
                  <div class="ml-3 w-0 flex-1">
                    <dl>
                      <dt class="text-xs font-medium text-base-content/70 truncate">
                        Pending Evaluations
                      </dt>
                      <dd class="text-sm font-medium text-base-content">
                        <%= @queue_status.queue_size %> in queue
                      </dd>
                    </dl>
                  </div>
                </div>
              </div>
            </div>

            <div class="bg-success/10 text-success-content overflow-hidden shadow rounded-lg">
              <div class="p-4">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <div class="w-8 h-8 bg-success rounded-md flex items-center justify-center">
                      <%= if @queue_status.current_evaluation do %>
                        <span class="text-success-content text-xs">⚡</span>
                      <% else %>
                        <span class="text-success-content text-xs">💤</span>
                      <% end %>
                    </div>
                  </div>
                  <div class="ml-3 w-0 flex-1">
                    <dl>
                      <dt class="text-xs font-medium text-base-content/70 truncate">
                        Current Status
                      </dt>
                      <dd class="text-sm font-medium text-base-content">
                        <%= if @queue_status.current_evaluation do %>
                          Running #<%= @queue_status.current_evaluation.eval_run_id %>
                        <% else %>
                          Idle
                        <% end %>
                      </dd>
                    </dl>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end

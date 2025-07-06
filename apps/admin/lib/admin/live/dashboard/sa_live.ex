defmodule Admin.SuperAdminLive do
  @moduledoc """
  LiveView for the super admin dashboard.

  This view provides an overview of application-wide statistics for super admins,
  including total user count, company count, employee count, subscription metrics,
  revenue data, and AI-related statistics. It subscribes to real-time updates for
  users, companies, employees, subscriptions, and feature requests via PubSub to
  ensure statistics stay current.
  """
  use Admin, :live_view
  alias Core.{Accounts, Companies, Subscriptions, Chat, FeatureRequests, AI}
  alias Admin.PageMeta
  alias Core.PubSub.DataSync

  @doc """
  Initializes the LiveView with application statistics and PubSub subscriptions.

  Collects summary statistics about users, companies, employees, subscriptions,
  revenue, chat sessions, feature requests, feedback, AI conversations, prompts,
  evaluations, and evaluation results. Sets up PubSub subscriptions for real-time
  updates to these metrics.
  """
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to all relevant topics for real-time updates
      DataSync.subscribe("companies", "all")
      DataSync.subscribe("users", "all")
      DataSync.subscribe("subscriptions", "all")
      DataSync.subscribe("profiles", "all")
      DataSync.subscribe("feature_requests", "all")

      # Subscribe to AI-related events for realtime statistics
      Phoenix.PubSub.subscribe(Admin.PubSub, "ai_usage")
      Phoenix.PubSub.subscribe(Admin.PubSub, "ai_evals")
      Phoenix.PubSub.subscribe(Admin.PubSub, "eval_runs")
    end

    stats = %{
      total_users: Accounts.count_users(),
      total_companies: Companies.count_companies(),
      total_subscriptions: Subscriptions.count_active_subscriptions(),
      total_revenue: Subscriptions.calculate_total_revenue(),

      # Chat statistics
      total_chats: Chat.count_sessions(),
      open_chats: Chat.count_sessions(status: "active"),
      closed_chats: Chat.count_sessions(status: "closed"),

      # Feature requests and feedback
      total_feature_requests: FeatureRequests.count_feature_requests(request_type: :feature),
      total_feedback: FeatureRequests.count_feature_requests(request_type: :feedback),

      # AI statistics
      total_conversations: AI.count_conversations(),
      total_prompts: AI.count_prompts(),
      total_evaluations: AI.count_evals(),
      total_eval_runs: AI.count_eval_runs(),

      # Evaluation results by status
      pending_eval_runs: AI.count_eval_runs(status: "pending"),
      running_eval_runs: AI.count_eval_runs(status: "running"),
      completed_eval_runs: AI.count_eval_runs(status: "completed"),
      failed_eval_runs: AI.count_eval_runs(status: "failed")
    }

    {:ok,
     socket
     |> assign(:stats, stats)
     |> PageMeta.assign_metadata(
       title: "Super Admin Dashboard",
       description: "Super Admin Dashboard",
       url: "/dashboard"
     )}
  end

  @impl true
  def handle_info({:created, %{type: :company, company: _company}}, socket) do
    {:noreply,
     update(socket, :stats, fn stats ->
       %{stats | total_companies: stats.total_companies + 1}
     end)}
  end

  # Handle company deletion
  def handle_info({:deleted, %{type: :company, id: _company_id}}, socket) do
    {:noreply,
     update(socket, :stats, fn stats ->
       %{stats | total_companies: stats.total_companies - 1}
     end)}
  end

  # Handle user creation
  def handle_info({:created, %{type: :user, user: _user}}, socket) do
    {:noreply,
     update(socket, :stats, fn stats ->
       %{stats | total_users: stats.total_users + 1}
     end)}
  end

  # Handle user deletion
  def handle_info({:deleted, %{type: :user, id: _user_id}}, socket) do
    {:noreply,
     update(socket, :stats, fn stats ->
       %{stats | total_users: stats.total_users - 1}
     end)}
  end

  # Handle subscription changes
  def handle_info({event, %{type: :subscription} = data}, socket) do
    case event do
      :created ->
        {:noreply,
         update(socket, :stats, fn stats ->
           %{
             stats
             | total_subscriptions: stats.total_subscriptions + 1,
               total_revenue: stats.total_revenue + (data.subscription.amount || 0)
           }
         end)}

      :deleted ->
        {:noreply,
         update(socket, :stats, fn stats ->
           %{
             stats
             | total_subscriptions: stats.total_subscriptions - 1,
               total_revenue: stats.total_revenue - (data.subscription.amount || 0)
           }
         end)}

      :updated ->
        # For updates, we only need to recalculate revenue if the amount changed
        if data.changes && Map.has_key?(data.changes, :amount) do
          old_amount = data.subscription.amount - data.changes.amount

          {:noreply,
           update(socket, :stats, fn stats ->
             %{stats | total_revenue: stats.total_revenue - old_amount + data.subscription.amount}
           end)}
        else
          {:noreply, socket}
        end
    end
  end

  # Handle feature request creation
  def handle_info({:created, _feature_request}, socket) do
    {:noreply,
     update(socket, :stats, fn stats ->
       %{
         stats
         | total_feature_requests: FeatureRequests.count_feature_requests(request_type: :feature),
           total_feedback: FeatureRequests.count_feature_requests(request_type: :feedback)
       }
     end)}
  end

  # Handle feature request deletion
  def handle_info({:deleted, _feature_request_id}, socket) do
    {:noreply,
     update(socket, :stats, fn stats ->
       %{
         stats
         | total_feature_requests: FeatureRequests.count_feature_requests(request_type: :feature),
           total_feedback: FeatureRequests.count_feature_requests(request_type: :feedback)
       }
     end)}
  end

  # Handle feature request updates
  def handle_info({:updated, _feature_request}, socket) do
    {:noreply,
     update(socket, :stats, fn stats ->
       %{
         stats
         | total_feature_requests: FeatureRequests.count_feature_requests(request_type: :feature),
           total_feedback: FeatureRequests.count_feature_requests(request_type: :feedback)
       }
     end)}
  end

  # Handle AI-related events for realtime statistics updates
  def handle_info({:usage_logged, _usage_log}, socket) do
    # AI usage was logged - no direct counter impact but could trigger timeline updates
    {:noreply, socket}
  end

  def handle_info({:eval_created, _eval}, socket) do
    {:noreply,
     update(socket, :stats, fn stats ->
       %{stats | total_evaluations: stats.total_evaluations + 1}
     end)}
  end

  def handle_info({:eval_updated, _eval}, socket) do
    # No counter changes for updates
    {:noreply, socket}
  end

  def handle_info({:eval_deleted, _eval}, socket) do
    {:noreply,
     update(socket, :stats, fn stats ->
       %{stats | total_evaluations: stats.total_evaluations - 1}
     end)}
  end

  def handle_info({:eval_run_updated, _eval_run}, socket) do
    # Recalculate eval run counts by status for accurate stats
    {:noreply,
     update(socket, :stats, fn stats ->
       %{
         stats
         | pending_eval_runs: AI.count_eval_runs(status: "pending"),
           running_eval_runs: AI.count_eval_runs(status: "running"),
           completed_eval_runs: AI.count_eval_runs(status: "completed"),
           failed_eval_runs: AI.count_eval_runs(status: "failed")
       }
     end)}
  end

  # Catch-all for any other events
  def handle_info(_message, socket), do: {:noreply, socket}

  defp dashboard_card(assigns) do
    ~H"""
    <div class={[
      "relative overflow-hidden rounded-lg p-4 shadow",
      if(Map.has_key?(@card, :link), do: "hover:bg-base-200 transition-colors", else: "")
    ]}>
      <div class="absolute rounded-md p-3">
        <.icon name={assigns.card.icon} class="h-8 w-8" />
      </div>
      <div class="ml-16">
        <p class="truncate text-sm font-medium text-base-content/70">{@card.title}</p>
        <p class="mt-1 text-3xl font-semibold text-base-content">{@card.value}</p>
      </div>
    </div>
    """
  end

  defp get_dashboard_sections(stats) do
    [
      %{
        title: "User & Company Statistics",
        cards: [
          %{
            title: "Total Users",
            value: stats.total_users,
            icon: "hero-users",
            link: ~p"/dashboard/users"
          },
          %{
            title: "Total Companies",
            value: stats.total_companies,
            icon: "hero-building-office-2",
            link: ~p"/dashboard/companies"
          },
          %{
            title: "Active Subscriptions",
            value: stats.total_subscriptions,
            icon: "hero-credit-card",
            link: ~p"/dashboard/subscriptions"
          },
          %{
            title: "Total Revenue",
            value: "$ #{stats.total_revenue}",
            icon: "hero-currency-dollar",
            link: ~p"/dashboard/subscriptions"
          }
        ]
      },
      %{
        title: "Chat Statistics",
        cards: [
          %{
            title: "Total Chats",
            value: stats.total_chats,
            icon: "hero-chat-bubble-oval-left",
            link: ~p"/dashboard/chat"
          },
          %{
            title: "Open Chats",
            value: stats.open_chats,
            icon: "hero-chat-bubble-oval-left-ellipsis"
          },
          %{
            title: "Closed Chats",
            value: stats.closed_chats,
            icon: "hero-chat-bubble-left"
          }
        ]
      },
      %{
        title: "Feature Requests & Feedback",
        cards: [
          %{
            title: "Feature Requests",
            value: stats.total_feature_requests,
            icon: "hero-light-bulb",
            link: ~p"/dashboard/feature-feedbacks"
          },
          %{
            title: "Feedback",
            value: stats.total_feedback,
            icon: "hero-chat-bubble-bottom-center-text",
            link: ~p"/dashboard/feature-feedbacks"
          }
        ]
      },
      %{
        title: "AI Statistics",
        cards: [
          %{
            title: "AI Conversations",
            value: stats.total_conversations,
            icon: "hero-cpu-chip",
            link: ~p"/dashboard/ai-chat"
          },
          %{
            title: "Total Prompts",
            value: stats.total_prompts,
            icon: "hero-document-text",
            link: ~p"/dashboard/ai-prompts"
          },
          %{
            title: "Total Evaluations",
            value: stats.total_evaluations,
            icon: "hero-clipboard-document-check",
            link: ~p"/dashboard/ai-evals"
          },
          %{
            title: "Total Eval Runs",
            value: stats.total_eval_runs,
            icon: "hero-chart-bar",
            link: ~p"/dashboard/ai-eval-results"
          },
          %{
            title: "AI Usage Timeline",
            value: "View",
            icon: "hero-clock",
            link: ~p"/dashboard/ai-results"
          }
        ]
      },
      %{
        title: "Evaluation Results by Status",
        cards: [
          %{
            title: "Pending Evaluations",
            value: stats.pending_eval_runs,
            icon: "hero-clock"
          },
          %{
            title: "Running Evaluations",
            value: stats.running_eval_runs,
            icon: "hero-play"
          },
          %{
            title: "Completed Evaluations",
            value: stats.completed_eval_runs,
            icon: "hero-check-circle"
          },
          %{
            title: "Failed Evaluations",
            value: stats.failed_eval_runs,
            icon: "hero-x-circle"
          }
        ]
      }
    ]
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :dashboard_sections, get_dashboard_sections(assigns.stats))

        ~H"""
    <div class="flex-1 h-[calc(100vh-100px)]">
      <.header>
        Super Admin Dashboard
        <:subtitle>View the stats of the application here</:subtitle>
      </.header>

      <div class="my-6 space-y-4 pb-6">
        <div :for={section <- @dashboard_sections}>
          <h3 class="text-lg font-medium text-base-content mb-4">{section.title}</h3>
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
            <div :for={card <- section.cards}>
              <%= if Map.has_key?(card, :link) do %>
                <a href={card.link} class="block">
                  <.dashboard_card card={card} />
                </a>
              <% else %>
                <.dashboard_card card={card} />
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end

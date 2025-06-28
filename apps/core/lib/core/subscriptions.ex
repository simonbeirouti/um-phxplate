defmodule Core.Subscriptions do
  @moduledoc """
  The Subscriptions context.

  This context manages the subscription system that enables paid plans within the application.
  It provides functionality for creating, updating, and managing subscriptions, including:

  - Plan management (listing, retrieving, and selecting plans)
  - User subscription management (creating, updating, and canceling subscriptions)
  - Integration with Stripe for payment processing
  - Subscription status tracking and updates
  - Administrative subscription management functions
  - Role-based upgrades based on subscription tier

  The context handles the complete subscription lifecycle, from checkout through Stripe,
  to tracking subscription status, to handling plan changes and cancellations.
  """

  import Ecto.Query, warn: false
  alias Core.Repo
  alias Core.Subscriptions.{Subscription, Plan, Purchase}
  alias Core.Accounts.User
  alias Core.Accounts
  alias Core.Companies
  alias Core.PubSub.DataSync
  alias Core.PlatformSetting
  require Logger

  require Logger

  @valid_statuses [:active, :canceled, :past_due, :incomplete, :trialing]
  @valid_tiers [:none, :small, :medium, :large]

  @doc """
  Gets a subscription by ID.

  Retrieves a subscription by its ID with the associated plan preloaded.

  ## Parameters
    - id: The ID of the subscription to retrieve

  ## Returns
    - The subscription with its plan preloaded
    - Raises Ecto.NoResultsError if the subscription doesn't exist
  """
  def get_subscription!(id), do: Repo.get!(Subscription, id) |> Repo.preload(:plan)

  @doc """
  Gets a subscription by stripe_subscription_id.

  Retrieves a subscription using its Stripe subscription ID.

  ## Parameters
    - stripe_subscription_id: The Stripe subscription ID to look up

  ## Returns
    - `{:ok, subscription}` if found, with plan preloaded
    - `{:error, :not_found}` if no matching subscription exists
  """
  def get_subscription_by_stripe_id(stripe_subscription_id) when is_binary(stripe_subscription_id) do
    case Repo.get_by(Subscription, stripe_subscription_id: stripe_subscription_id) do
      nil -> {:error, :not_found}
      subscription -> {:ok, subscription |> Repo.preload(:plan)}
    end
  end

  @doc """
  Creates a subscription.

  Creates a new subscription record, broadcasts the creation event via PubSub,
  and updates the user's role based on the subscription plan if necessary.

  ## Parameters
    - attrs: Map of attributes for the new subscription

  ## Returns
    - `{:ok, subscription}` on success
    - `{:error, changeset}` on validation failure
  """
  def create_subscription(attrs \\ %{}) do
    %Subscription{}
    |> Subscription.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, subscription} = result ->
        # Broadcast creation
        DataSync.broadcast("subscriptions", subscription.user_id,
          {:created, %{type: :subscription, subscription: subscription}}
        )
        DataSync.broadcast("subscriptions", "all",
          {:created, %{type: :subscription, subscription: subscription}}
        )

        # Track subscription creation
        subscription_with_plan = subscription |> Repo.preload(:plan)
        track_subscription_entity_change(
          "subscription_created",
          subscription_with_plan,
          %{id: subscription.user_id},
          %{
            "plan_name" => subscription_with_plan.plan.name,
            "plan_tier" => subscription.paid_tier,
            "status" => subscription.subscription_status
          }
        )

        # Update user role based on the new subscription's plan
        try do
          user = Accounts.get_user!(subscription.user_id)
          plan = get_plan!(subscription.plan_id)
          maybe_update_user_role_from_plan(user, plan)
        rescue
          e in Ecto.NoResultsError -> Logger.error("Failed to find user or plan for role update during subscription creation: #{inspect(e)}")
          e -> Logger.error("Error during role update in create_subscription: #{inspect(e)}, stacktrace: #{inspect(__STACKTRACE__)}")
        end

        result
      error -> error
    end
  end

  @doc """
  Updates a subscription.
  """
  def update_subscription(%Subscription{} = subscription, attrs) do
    subscription
    |> Subscription.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_subscription} = result ->
        # Broadcast update
        DataSync.broadcast("subscriptions", updated_subscription.user_id,
          {:updated, %{type: :subscription, subscription: updated_subscription}}
        )
        DataSync.broadcast("subscriptions", "all",
          {:updated, %{type: :subscription, subscription: updated_subscription}}
        )

        # Track subscription update
        subscription_with_plan = updated_subscription |> Repo.preload(:plan)
        track_subscription_entity_change(
          "subscription_updated",
          subscription_with_plan,
          %{id: updated_subscription.user_id},
          %{
            "plan_name" => subscription_with_plan.plan.name,
            "plan_tier" => updated_subscription.paid_tier,
            "status" => updated_subscription.subscription_status,
            "changes" => attrs
          }
        )

        # Update user role based on the updated subscription's plan
        try do
          user = Accounts.get_user!(updated_subscription.user_id)
          plan = get_plan!(updated_subscription.plan_id) # Assumes plan_id reflects the new plan
          maybe_update_user_role_from_plan(user, plan)
        rescue
          e in Ecto.NoResultsError -> Logger.error("Failed to find user or plan for role update during subscription update: #{inspect(e)}")
          e -> Logger.error("Error during role update in update_subscription: #{inspect(e)}, stacktrace: #{inspect(__STACKTRACE__)}")
        end

        result
      error -> error
    end
  end

  @doc """
  Deletes a subscription.
  """
  def delete_subscription(%Subscription{} = subscription) do
    Repo.delete(subscription)
    |> case do
      {:ok, deleted_subscription} = result ->
        # Broadcast deletion
        DataSync.broadcast("subscriptions", deleted_subscription.user_id,
          {:deleted, %{type: :subscription, id: deleted_subscription.id}}
        )
        DataSync.broadcast("subscriptions", "all",
          {:deleted, %{type: :subscription, id: deleted_subscription.id}}
        )
        result
      error -> error
    end
  end

  @doc """
  Gets a user's subscription.

  Retrieves the subscription associated with a specific user,
  with the subscription plan preloaded.

  ## Parameters
    - user_id: The ID of the user whose subscription to retrieve

  ## Returns
    - The subscription with its plan preloaded if found
    - nil if the user has no subscription
  """
  def get_user_subscription(user_id) do
    Subscription
    |> where([s], s.user_id == ^user_id)
    |> Repo.one()
    |> Repo.preload(:plan)
  end

  @doc """
  Lists all plans grouped by tier with both monthly and yearly options.

  Groups available subscription plans by tier, separating monthly and yearly
  billing options for each tier, making it easier to display plan options.

  ## Returns
    - A map of tiers, each containing their monthly and yearly plans
  """
  def list_all_plans do
    plans =
      Plan
      |> order_by([p], asc: p.unit_amount)
      |> Repo.all()

    # Separate subscription plans from single purchase products
    {subscription_plans, single_purchase_plans} =
      Enum.split_with(plans, &(&1.product_type == :subscription))

    # Group subscription plans by tier
    subscription_structure =
      subscription_plans
      |> Enum.group_by(& &1.metadata["tier"])
      |> Enum.map(fn {tier, tier_plans} ->
        {tier,
         %{
           monthly: Enum.find(tier_plans, &(&1.interval == "month")),
           yearly: Enum.find(tier_plans, &(&1.interval == "year"))
         }}
      end)
      |> Enum.into(%{})

    # Add single purchase products as a separate category
    Map.put(subscription_structure, :single_purchase, single_purchase_plans)
  end

  @doc """
  Lists all plans for a specific interval (month or year) ordered by amount.
  """
  def list_plans_by_interval(interval) when interval in ["month", "year"] do
    Plan
    |> where([p], p.interval == ^interval)
    |> order_by([p], asc: p.unit_amount)
    |> Repo.all()
  end

  @doc """
  Lists all single purchase products ordered by amount.
  """
  def list_single_purchase_products do
    Plan
    |> where([p], p.product_type == :single_purchase)
    |> order_by([p], asc: p.unit_amount)
    |> Repo.all()
  end

  @doc """
  Gets a plan by ID.

  Retrieves a subscription plan by its ID.

  ## Parameters
    - id: The ID of the plan to retrieve

  ## Returns
    - The plan if found
    - Raises Ecto.NoResultsError if the plan doesn't exist
  """
  def get_plan!(id), do: Repo.get!(Plan, id)

  @doc """
  Gets a plan by Stripe price ID.
  """
  def get_plan_by_stripe_price_id(stripe_price_id) do
    Repo.get_by(Plan, stripe_price_id: stripe_price_id)
  end

  @doc """
  Updates a plan.

  Updates an existing plan with the provided attributes.

  ## Parameters
    - plan: The plan struct to update
    - attrs: Map of attributes to update

  ## Returns
    - `{:ok, plan}` on success
    - `{:error, changeset}` on validation failure
  """
  def update_plan(%Plan{} = plan, attrs) do
    # Convert features map if it's provided
    attrs = if attrs["features"] do
      Map.put(attrs, "features", process_features_map(attrs["features"]))
    else
      attrs
    end

    # Convert metadata if tier is provided
    attrs = if attrs["tier"] do
      metadata = Map.get(attrs, "metadata", plan.metadata || %{})
      updated_metadata = Map.put(metadata, "tier", attrs["tier"])
      attrs
      |> Map.put("metadata", updated_metadata)
      |> Map.delete("tier")
    else
      attrs
    end

    plan
    |> Plan.changeset(attrs)
    |> Repo.update()
  end

  # Helper function to process features map from form params
  defp process_features_map(features) when is_map(features) do
    features
    |> Enum.reject(fn {key, value} ->
      key == "" or value == "" or String.starts_with?(key, "new_feature_")
    end)
    |> Enum.into(%{})
  end

  @doc """
  Creates a checkout session for a user to subscribe to a plan.

  Integrates with Stripe to create a checkout session for a user to subscribe
  to a specific plan. Handles both new subscriptions and plan changes for
  existing subscribers.

  ## Parameters
    - user: The user who will be subscribing
    - plan: The plan the user is subscribing to

  ## Returns
    - `{:ok, session}` with the Stripe checkout session on success
    - `{:error, reason}` on failure
  """
  def create_checkout_session(%User{} = user, %Plan{} = plan) do
    stripe_price_id = plan.stripe_price_id

    if is_nil(stripe_price_id) do
      {:error, "Plan does not have a Stripe price ID"}
    else
      # Use the router routes for success and cancel URLs
      base_url = Application.get_env(:core, :base_url) || "https://#{System.get_env("PHX_HOST")}"

      # Ensure base_url doesn't end with a slash
      base_url = String.trim_trailing(base_url, "/")

      # Make sure we have a valid base URL, fallback to the PHX_HOST directly if needed
      base_url = if String.contains?(base_url, "://"), do: base_url, else: "https://#{System.get_env("PHX_HOST")}"

      success_url = "#{base_url}/callbacks/stripe/success?session_id={CHECKOUT_SESSION_ID}"
      cancel_url = "#{base_url}/callbacks/stripe/cancel"

      # Log the URLs for debugging
      Logger.info("Creating Stripe checkout with URLs: success=#{success_url}, cancel=#{cancel_url}")

      subscription = get_user_subscription(user.id)

      session_params = if subscription && subscription.stripe_customer_id do
        # For existing subscriptions, we'll create a new subscription and cancel the old one after success
        # This is the recommended approach by Stripe for changing plans

        # Get the current plan details
        current_plan = subscription.plan
        new_plan = plan

        # Determine if this is an upgrade (higher price plan)
        is_upgrade = current_plan && new_plan && new_plan.unit_amount > current_plan.unit_amount

        base_params = %{
          mode: "subscription",
          customer: subscription.stripe_customer_id,
          success_url: success_url,
          cancel_url: cancel_url,
          client_reference_id: user.id,
          payment_method_types: ["card"],
          line_items: [
            %{
              price: stripe_price_id,
              quantity: 1
            }
          ]
        }

        # For upgrades, we'll handle the proration manually since Stripe's proration_behavior has limitations
        if is_upgrade do
          # Calculate days remaining in current subscription period
          today = DateTime.utc_now()
          period_end = subscription.subscription_period_end

          # Calculate total days in billing period (approximation)
          total_days_in_period =
            case current_plan.interval do
              "month" -> 30 # Approximate for simplicity
              "year" -> 365
              _ -> 30
            end

          # Calculate days remaining and used
          days_remaining = DateTime.diff(period_end, today, :day)

          # Calculate percentage of period remaining
          percent_remaining = days_remaining / total_days_in_period

          # Calculate prorated amount of current subscription that should be credited
          current_plan_remaining_value = current_plan.unit_amount * percent_remaining

          # Store this information in metadata for reference
          Map.merge(base_params, %{
            subscription_data: %{
              metadata: %{
                previous_plan: current_plan.name,
                previous_amount: current_plan.unit_amount,
                upgrade_date: DateTime.utc_now() |> DateTime.to_iso8601(),
                days_remaining: days_remaining,
                percent_remaining: Float.round(percent_remaining * 100, 2),
                credit_amount: trunc(current_plan_remaining_value)
              }
            }
          })
        else
          base_params
        end
      else
        # For new subscriptions
        base_params = %{
          payment_method_types: ["card"],
          line_items: [
            %{
              price: stripe_price_id,
              quantity: 1
            }
          ],
          mode: "subscription",
          success_url: success_url,
          cancel_url: cancel_url,
          client_reference_id: user.id
        }

        # Add customer info
        if subscription && subscription.stripe_customer_id do
          Map.put(base_params, :customer, subscription.stripe_customer_id)
        else
          # Create customer with user email for new subscriptions
          Map.put(base_params, :customer_email, user.email)
        end
      end

      Logger.info("Creating Stripe checkout session with params: #{inspect(session_params)}")

      case Stripe.Session.create(session_params) do
        {:ok, session} ->
          Logger.info("Created Stripe checkout session: #{session.id}")
          {:ok, session}
        {:error, error} ->
          Logger.error("Failed to create Stripe checkout session: #{inspect(error)}")
          {:error, error}
      end
    end
  end

  @doc """
  Updates a user's subscription to a new plan.

  Creates a Stripe checkout session for changing to a new subscription plan,
  tracks the activity, and returns the session for redirecting the user.

  ## Parameters
    - user: The user whose subscription to update
    - plan: The new plan to subscribe to

  ## Returns
    - `{:ok, session}` with the Stripe checkout session on success
    - `{:error, reason}` on failure
  """
  def change_subscription_plan(%User{} = user, %Plan{} = plan) do
    # Get the user's current subscription
    subscription = get_user_subscription(user.id)

    if subscription && subscription.stripe_subscription_id do
      # Get the current plan details
      current_plan = subscription.plan
      new_plan = plan

      # Determine if this is an upgrade (higher price plan)
      is_upgrade = current_plan && new_plan && new_plan.unit_amount > current_plan.unit_amount

      if is_upgrade do
        # First, check if there's a scheduled downgrade and clear it if exists
        if subscription.metadata && subscription.metadata["scheduled_plan_change"] do
          # Clear the scheduled downgrade by updating the subscription in Stripe
          case Stripe.Subscription.retrieve(subscription.stripe_subscription_id) do
            {:ok, stripe_subscription} ->
              # Get the first subscription item ID (assuming single plan subscription)
              [subscription_item | _] = stripe_subscription.items.data
              subscription_item_id = subscription_item.id

              # Update the subscription to keep the current plan (cancel the scheduled downgrade)
              Stripe.Subscription.update(subscription.stripe_subscription_id, %{
                items: [
                  %{
                    id: subscription_item_id,
                    price: current_plan.stripe_price_id
                  }
                ]
              })

              # Get the scheduled plan change details before clearing
              scheduled_plan_id = subscription.metadata["scheduled_plan_change"]["plan_id"]
              _scheduled_plan = nil

              # Try to get the scheduled plan details if possible
              try do
                scheduled_plan = Core.Subscriptions.get_plan!(scheduled_plan_id)
                Logger.info("Found scheduled plan change to #{scheduled_plan.name}")
              rescue
                _ -> Logger.info("Could not find scheduled plan with ID #{scheduled_plan_id}")
              end

              # Clear the metadata in our local database
              {:ok, updated_subscription} = update_subscription(subscription, %{metadata: %{}})

              Logger.info("Cleared scheduled downgrade before processing upgrade")

              # Return the updated subscription for further processing
              _subscription = updated_subscription
            {:error, error} ->
              Logger.error("Failed to clear scheduled downgrade: #{inspect(error)}")
          end
        end

        # For upgrades, we'll handle it with a different approach since Stripe's proration_behavior has limitations
        # 1. Calculate the prorated credit from the current subscription
        # 2. Create a one-time coupon for the prorated amount
        # 3. Apply the coupon to the new subscription
        # 4. Cancel the old subscription after the new one is created

        # Calculate days remaining in current subscription period
        today = DateTime.utc_now()
        period_end = subscription.subscription_period_end

        # Calculate total days in billing period (approximation)
        total_days_in_period =
          case current_plan.interval do
            "month" -> 30 # Approximate for simplicity
            "year" -> 365
            _ -> 30
          end

        # Calculate days remaining and used
        days_remaining = DateTime.diff(period_end, today, :day)

        # Calculate percentage of period remaining
        percent_remaining = days_remaining / total_days_in_period

        # Calculate prorated amount of current subscription that should be credited
        # For yearly plans, this is a significant amount that needs to be properly credited
        current_plan_remaining_value =
          if current_plan.interval == "year" do
            # For yearly plans, calculate the full remaining value
            # This ensures proper credit for expensive yearly plans
            trunc(current_plan.unit_amount * percent_remaining)
          else
            # For monthly plans, use the standard calculation
            trunc(current_plan.unit_amount * percent_remaining)
          end

        # Log the credit calculation for debugging
        Logger.info("Calculated credit for upgrade: #{current_plan_remaining_value} (#{percent_remaining * 100}% remaining of #{current_plan.unit_amount})")

        # Create a checkout session for the new plan
        success_url = "#{Application.get_env(:core, :base_url)}/callbacks/stripe/success?session_id={CHECKOUT_SESSION_ID}&is_upgrade=true&old_subscription_id=#{subscription.stripe_subscription_id}"
        cancel_url = "#{Application.get_env(:core, :base_url)}/callbacks/stripe/cancel"

        # Create checkout session parameters
        session_params = %{
          mode: "subscription",
          customer: subscription.stripe_customer_id,
          success_url: success_url,
          cancel_url: cancel_url,
          client_reference_id: user.id,
          payment_method_types: ["card"],
          line_items: [
            %{
              price: new_plan.stripe_price_id,
              quantity: 1
            }
          ],
          subscription_data: %{
            metadata: %{
              previous_plan: current_plan.name,
              previous_amount: current_plan.unit_amount,
              upgrade_date: DateTime.utc_now() |> DateTime.to_iso8601(),
              days_remaining: days_remaining,
              percent_remaining: Float.round(percent_remaining * 100, 2),
              credit_amount: current_plan_remaining_value,
              is_upgrade: true,
              old_subscription_id: subscription.stripe_subscription_id
            }
          }
        }

        # If there's a significant credit amount, create a discount
        if current_plan_remaining_value > 0 do
          # Create a unique coupon ID for this upgrade
          coupon_id = "upgrade_#{user.id}_#{DateTime.utc_now() |> DateTime.to_unix()}"

          # Create a one-time coupon for the prorated amount
          # Ensure the coupon name is not too long (Stripe has a 40 character limit)
          coupon_name = "Credit for #{current_plan.interval}ly plan"

          coupon_params = %{
            id: coupon_id,
            amount_off: current_plan_remaining_value,
            currency: current_plan.currency,
            duration: "once",
            name: coupon_name
          }

          case Stripe.Coupon.create(coupon_params) do
            {:ok, coupon} ->
              # Apply the coupon to the checkout session
              session_params = Map.put(session_params, :discounts, [%{coupon: coupon.id}])

              Logger.info("Created coupon #{coupon.id} for upgrade credit of #{current_plan_remaining_value}")

              # Create the checkout session with the coupon applied
              case Stripe.Session.create(session_params) do
                {:ok, session} ->
                  # Track the subscription change attempt
                  track_subscription_change(
                    "subscription_plan_upgrade",
                    user,
                    user,
                    %{
                      "plan_id" => plan.id,
                      "plan_name" => plan.name,
                      "previous_plan" => current_plan.name,
                      "credit_amount" => current_plan_remaining_value,
                      "coupon_id" => coupon.id
                    }
                  )

                  {:ok, session}
                {:error, error} ->
                  Logger.error("Failed to create Stripe checkout session for upgrade: #{inspect(error)}")
                  {:error, error}
              end

            {:error, error} ->
              Logger.error("Failed to create coupon for upgrade: #{inspect(error)}")

              # Fall back to creating a session without a coupon
              case Stripe.Session.create(session_params) do
                {:ok, session} -> {:ok, session}
                {:error, error} -> {:error, error}
              end
          end
        else
          # No significant credit to apply, just create the session
          case Stripe.Session.create(session_params) do
            {:ok, session} ->
              # Track the subscription change attempt
              track_subscription_change(
                "subscription_plan_upgrade",
                user,
                user,
                %{
                  "plan_id" => plan.id,
                  "plan_name" => plan.name,
                  "previous_plan" => current_plan.name
                }
              )

              {:ok, session}
            {:error, error} ->
              Logger.error("Failed to create Stripe checkout session for upgrade: #{inspect(error)}")
              {:error, error}
          end
        end
      else
        # For downgrades, follow industry standard practice:
        # 1. Keep current subscription until end of billing period
        # 2. Schedule the downgrade to take effect at the next billing cycle
        # 3. Don't charge the customer again until the end of their current billing period

        # Determine if this is a downgrade (lower price plan)
        is_downgrade = current_plan && new_plan && new_plan.unit_amount < current_plan.unit_amount

        if is_downgrade do
          # For downgrades, we'll schedule the change at the end of the current billing period
          Logger.info("Processing subscription downgrade from #{current_plan.name} to #{new_plan.name}")

          # Get the current subscription from Stripe to ensure we have the latest data
          case Stripe.Subscription.retrieve(subscription.stripe_subscription_id) do
            {:ok, stripe_subscription} ->
              # Schedule the downgrade at the end of the current billing period
              # by updating the subscription with the new price, but setting proration_behavior to 'none'
              # and using the current_period_end as the billing_cycle_anchor

              # Get the first subscription item ID (assuming single plan subscription)
              [subscription_item | _] = stripe_subscription.items.data
              subscription_item_id = subscription_item.id

              # Update the subscription to change plans at the end of the billing period
              update_params = %{
                proration_behavior: "none",
                items: [
                  %{
                    id: subscription_item_id,
                    price: new_plan.stripe_price_id
                  }
                ],
                metadata: %{
                  downgrade_date: DateTime.utc_now() |> DateTime.to_iso8601(),
                  previous_plan: current_plan.name,
                  new_plan: new_plan.name
                }
              }

              case Stripe.Subscription.update(subscription.stripe_subscription_id, update_params) do
                {:ok, updated_subscription} ->
                  # Update the local subscription record to reflect the scheduled change
                  # but keep the current plan until the change takes effect
                  {:ok, _updated_local_subscription} = update_subscription(subscription, %{
                    metadata: %{
                      scheduled_plan_change: %{
                        plan_id: new_plan.id,
                        effective_date: DateTime.from_unix!(updated_subscription.current_period_end)
                      }
                    }
                  })

                  # Track the subscription change attempt
                  track_subscription_change(
                    "subscription_plan_downgrade_scheduled",
                    user,
                    user,
                    %{
                      "current_plan_id" => current_plan.id,
                      "current_plan_name" => current_plan.name,
                      "new_plan_id" => new_plan.id,
                      "new_plan_name" => new_plan.name,
                      "effective_date" => DateTime.from_unix!(updated_subscription.current_period_end) |> DateTime.to_iso8601()
                    }
                  )

                  # Return success with the updated subscription
                  {:ok, %{
                    scheduled_downgrade: true,
                    current_plan: current_plan.name,
                    new_plan: new_plan.name,
                    effective_date: DateTime.from_unix!(updated_subscription.current_period_end)
                  }}

                {:error, error} ->
                  Logger.error("Failed to schedule subscription downgrade: #{inspect(error)}")
                  {:error, error}
              end

            {:error, error} ->
              Logger.error("Failed to retrieve subscription from Stripe: #{inspect(error)}")
              {:error, error}
          end
        else
          # For lateral changes (same price), use the standard checkout session
          case create_checkout_session(user, plan) do
            {:ok, session} ->
              # Track the subscription change attempt
              track_subscription_change(
                "subscription_plan_change",
                user,
                user,
                %{"plan_id" => plan.id, "plan_name" => plan.name}
              )

              {:ok, session}
            error -> error
          end
        end
      end
    else
      # No current subscription, create a new one
      case create_checkout_session(user, plan) do
        {:ok, session} ->
          # Track the subscription change attempt
          track_subscription_change(
            "subscription_plan_change",
            user,
            user,
            %{"plan_id" => plan.id, "plan_name" => plan.name}
          )

          {:ok, session}
        error -> error
      end
    end
  end

  @doc """
  Cancels a user's subscription.

  Updates the subscription in Stripe to cancel at the end of the current billing period,
  updates the local subscription record status, and tracks the cancellation activity.

  ## Parameters
    - user: The user whose subscription to cancel

  ## Returns
    - `{:ok, subscription}` with the updated subscription on success
    - `{:error, reason}` on failure
  """
  def cancel_subscription(%User{} = user) do
    case get_user_subscription(user.id) do
      nil ->
        {:error, "User does not have an active subscription"}

      %Subscription{stripe_subscription_id: subscription_id} = subscription ->
        case Stripe.Subscription.update(subscription_id, %{cancel_at_period_end: true}) do
          {:ok, _stripe_sub} ->
            # Update local subscription record
            case update_subscription(subscription, %{subscription_status: :canceled}) do
              {:ok, updated_subscription} ->
                # Track the cancellation
                track_subscription_change(
                  "subscription_cancelled",
                  user,
                  nil,
                  %{
                    "plan" => subscription.plan.name,
                    "status" => "canceled",
                    "end_date" => Calendar.strftime(subscription.subscription_period_end, "%Y-%m-%d")
                  }
                )
                {:ok, updated_subscription}
              error -> error
            end

          {:error, error} ->
            Logger.error("Failed to cancel Stripe subscription: #{inspect(error)}")
            {:error, error}
        end
    end
  end

  @doc """
  Process a charge from Stripe.
  """
  def process_charge(type, %Stripe.Charge{} = charge) do
    Logger.info("Processing #{type} charge: #{charge.id}")

    # Find the subscription by customer ID
    case Repo.get_by(Subscription, stripe_customer_id: charge.customer) do
      nil ->
        Logger.error("No subscription found for customer #{charge.customer}")
        {:error, :subscription_not_found}

      subscription ->
        # Log the successful payment
        Logger.info("Successful payment for subscription #{subscription.id}")
        {:ok, subscription}
    end
  end

  @doc """
  Counts total active subscriptions on the platform.

  Returns the count of subscriptions with an active status.

  ## Returns
    - Integer count of active subscriptions
  """
  def count_active_subscriptions do
    Subscription
    |> where([s], s.subscription_status == :active)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Calculates total revenue on the platform.

  Sums the unit amounts of all active subscription plans.

  ## Returns
    - Integer total revenue amount (in cents)
  """
  def calculate_total_revenue do
    Subscription
    |> where([s], s.subscription_status == :active)
    |> join(:inner, [s], p in assoc(s, :plan))
    |> select([s, p], sum(p.unit_amount))
    |> Repo.one() || 0
  end

  @doc """
  Creates an admin subscription for a user (super admin only).

  ## Parameters
    - user_id: The ID of the user to create a subscription for
    - tier: The subscription tier (:small, :medium, :large)
    - status: The subscription status
    - actor: The user performing the action (must be super admin)

  ## Returns
    - `{:ok, subscription}` on success
    - `{:error, :unauthorized}` if actor is not super admin
    - `{:error, reason}` on other failures
  """
  def admin_create_subscription(user_id, tier, status, actor) when tier in @valid_tiers and status in @valid_statuses do
    case actor do
      %User{role: :super_admin} ->
        with {:ok, plan} <- find_plan_by_tier(tier) do
          attrs = %{
            user_id: user_id,
            paid_tier: tier,
            plan_id: plan.id,
            subscription_status: status,
            stripe_customer_id: "admin_created_#{user_id}",
            stripe_subscription_id: "admin_created_#{user_id}"
          }
          create_subscription(attrs)
        end
      _ ->
        {:error, :unauthorized}
    end
  end
  def admin_create_subscription(_user_id, _tier, _status, _actor), do: {:error, :invalid_parameters}

  @doc """
  Admin-only function to update a subscription's status.
  This bypasses Stripe and only updates the local database record.
  Should only be used by super admins for administrative purposes.
  """
  def admin_update_subscription_status(subscription, status, actor)
  def admin_update_subscription_status(%Subscription{} = subscription, status, actor) when status in @valid_statuses do
    case actor do
      %User{role: :super_admin} ->
        update_subscription(subscription, %{subscription_status: status})
      _ ->
        {:error, :unauthorized}
    end
  end
  def admin_update_subscription_status(_subscription, _status, _actor), do: {:error, :invalid_status}

  @doc """
  Admin-only function to update a subscription's tier.
  This bypasses Stripe and only updates the local database record.
  Should only be used by super admins for administrative purposes.
  """
  def admin_update_subscription_tier(subscription, tier, actor)
  def admin_update_subscription_tier(%Subscription{} = subscription, :none, actor) do
    case actor do
      %User{role: :super_admin} ->
        # Special handling for downgrading to no subscription
        case delete_subscription(subscription) do
          {:ok, _deleted} ->
            track_subscription_change(
              "subscription_tier_update",
              %{id: subscription.user_id},
              actor,
              %{"tier" => "none"}
            )
            {:ok, nil}
          error -> error
        end
      _ ->
        {:error, :unauthorized}
    end
  end
  def admin_update_subscription_tier(%Subscription{} = subscription, tier, actor) when tier in @valid_tiers do
    case actor do
      %User{role: :super_admin} ->
        with {:ok, plan} <- find_plan_by_tier(tier) do
          update_subscription(subscription, %{paid_tier: tier, plan_id: plan.id})
        end
      _ ->
        {:error, :unauthorized}
    end
  end
  def admin_update_subscription_tier(_subscription, _tier, _actor), do: {:error, :invalid_tier}

  # Helper function to track subscription changes
  defp track_subscription_change(action, user, actor, additional_data) do
    tracking_actor = actor || user
    additional_data = if is_nil(additional_data), do: %{}, else: additional_data
    Core.Tracking.track_user_activity(action, user, tracking_actor, additional_data)
  end

  # Helper function to track subscription entity changes
  defp track_subscription_entity_change(action, subscription, actor, additional_data) do
    tracking_actor = actor || %{id: subscription.user_id}
    additional_data = if is_nil(additional_data), do: %{}, else: additional_data
    Core.Tracking.track_subscription_activity(action, subscription, tracking_actor, additional_data)
  end

  # Helper function to track plan changes
  defp track_plan_activity(action, plan, actor, changes, metadata) do
    Core.Tracking.track_plan_activity(action, plan, actor, changes, metadata)
  end

  # Helper function to find plan by tier
  defp find_plan_by_tier(tier) when tier in @valid_tiers do
    tier_string = Atom.to_string(tier)

    list_all_plans()
    |> Enum.find(fn {t, _} -> t == tier_string end)
    |> case do
      {_, %{monthly: plan}} when not is_nil(plan) -> {:ok, plan}
      _ -> {:error, :plan_not_found}
    end
  end

  # New helper function to update user role based on plan
  defp maybe_update_user_role_from_plan(%User{} = user, %Plan{} = plan) do
    current_role = user.role
    # Assuming plan.metadata["tier"] is "small", "medium", or "large" (as strings)
    plan_tier = Map.get(plan.metadata, "tier")

    new_role =
      cond do
        # Upgrade from :basic to :admin if plan tier is "small", "medium" or "large"
        # and user is currently :basic.
        current_role == :basic && plan_tier in ["small", "medium", "large"] ->
          :admin
        # Add other rules here if needed (e.g., downgrades, other role tiers).
        # For now, only this specific upgrade path is handled.
        true ->
          nil # No role change based on current logic
      end

    if new_role && current_role != new_role do
      Logger.info("Attempting to change user #{user.id} role from #{current_role} to #{new_role} based on plan #{plan.name} (tier: #{plan_tier})")
      # Passing `nil` as the actor, so `Accounts.update_user` will log the user themselves
      # as initiating the change (via subscription action).
      case Accounts.update_user(user, %{"role" => new_role}, nil) do
        {:ok, updated_user} ->
          Logger.info("User #{updated_user.id} role successfully changed to #{updated_user.role}")
          # Note: If LiveViews need to react immediately to this role change across the user's sessions,
          # `Core.Accounts.update_user/3` would ideally broadcast this user update via PubSub.
          # This change focuses on ensuring the database is updated.
          :ok
        {:error, changeset} ->
          Logger.error("Failed to update user #{user.id} role to #{new_role}: #{inspect(changeset.errors)}")
          {:error, :role_update_failed}
      end
    else
      Logger.info("No role change for user #{user.id} (current role: #{current_role}, plan: #{plan.name}, tier: #{plan_tier}). Calculated new role: #{new_role || "none"}")
      :no_role_change_needed
    end
  end

  # Purchase-related functions

  @doc """
  Lists all plans by product type (subscription or single_purchase).
  """
  def list_plans_by_product_type(product_type) when product_type in [:subscription, :single_purchase] do
    Plan
    |> where([p], p.product_type == ^product_type)
    |> order_by([p], asc: p.unit_amount)
    |> Repo.all()
  end

  @doc """
  Gets a purchase by ID.
  """
  def get_purchase!(id), do: Repo.get!(Purchase, id) |> Repo.preload([:user, :plan])

  @doc """
  Gets a purchase by Stripe payment intent ID.
  """
  def get_purchase_by_stripe_payment_intent_id(stripe_payment_intent_id) when is_binary(stripe_payment_intent_id) do
    case Repo.get_by(Purchase, stripe_payment_intent_id: stripe_payment_intent_id) do
      nil -> {:error, :not_found}
      purchase -> {:ok, purchase |> Repo.preload([:user, :plan])}
    end
  end

  @doc """
  Creates a purchase.
  """
  def create_purchase(attrs \\ %{}) do
    %Purchase{}
    |> Purchase.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, purchase} = result ->
        # Broadcast creation
        DataSync.broadcast("purchases", purchase.user_id,
          {:created, %{type: :purchase, purchase: purchase}}
        )
        DataSync.broadcast("purchases", "all",
          {:created, %{type: :purchase, purchase: purchase}}
        )
        result
      error -> error
    end
  end

  @doc """
  Updates a purchase.
  """
  def update_purchase(%Purchase{} = purchase, attrs) do
    purchase
    |> Purchase.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_purchase} = result ->
        # Broadcast update
        DataSync.broadcast("purchases", updated_purchase.user_id,
          {:updated, %{type: :purchase, purchase: updated_purchase}}
        )
        DataSync.broadcast("purchases", "all",
          {:updated, %{type: :purchase, purchase: updated_purchase}}
        )
        result
      error -> error
    end
  end

  @doc """
  Updates a purchase status.
  """
  def update_purchase_status(%Purchase{} = purchase, attrs) do
    purchase
    |> Purchase.status_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_purchase} = result ->
        # Broadcast status update
        DataSync.broadcast("purchases", updated_purchase.user_id,
          {:status_updated, %{type: :purchase, purchase: updated_purchase}}
        )
        DataSync.broadcast("purchases", "all",
          {:status_updated, %{type: :purchase, purchase: updated_purchase}}
        )
        result
      error -> error
    end
  end

  @doc """
  Lists all purchases for a user.
  """
  def list_user_purchases(user_id) do
    Purchase
    |> where([p], p.user_id == ^user_id)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
    |> Repo.preload([:plan])
  end

  @doc """
  Lists all purchases with pagination.
  """
  def list_purchases(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    Purchase
    |> limit(^limit)
    |> offset(^offset)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
    |> Repo.preload([:user, :plan])
  end

  @doc """
  Creates a checkout session for a single purchase product.
  """
  def create_single_purchase_checkout_session(%User{} = user, %Plan{product_type: :single_purchase} = plan) do
    stripe_price_id = plan.stripe_price_id

    if is_nil(stripe_price_id) do
      {:error, "Plan does not have a Stripe price ID"}
    else
      base_url = Application.get_env(:core, :base_url) || "https://#{System.get_env("PHX_HOST")}"
      base_url = String.trim_trailing(base_url, "/")
      base_url = if String.contains?(base_url, "://"), do: base_url, else: "https://#{System.get_env("PHX_HOST")}"

      success_url = "#{base_url}/callbacks/stripe/purchase_success?session_id={CHECKOUT_SESSION_ID}"
      cancel_url = "#{base_url}/callbacks/stripe/cancel"

      Logger.info("Creating Stripe single purchase checkout with URLs: success=#{success_url}, cancel=#{cancel_url}")

      session_params = %{
        payment_method_types: ["card"],
        line_items: [
          %{
            price: stripe_price_id,
            quantity: 1
          }
        ],
        mode: "payment", # Single payment mode for one-time purchases
        success_url: success_url,
        cancel_url: cancel_url,
        client_reference_id: user.id,
        metadata: %{
          user_id: user.id,
          plan_id: plan.id,
          product_type: "single_purchase"
        }
      }

      # Add customer info if available
      session_params = if user.email do
        Map.put(session_params, :customer_email, user.email)
      else
        session_params
      end

      case Stripe.Session.create(session_params) do
        {:ok, session} ->
          Logger.info("Single purchase checkout session created: #{session.id}")
          {:ok, session}
        {:error, error} ->
          Logger.error("Failed to create single purchase checkout session: #{inspect(error)}")
          {:error, error}
      end
    end
  end

  @doc """
  Handles successful single purchase payment from Stripe webhook.
  """
  def handle_successful_single_purchase_payment(payment_intent) do
    user_id = payment_intent.metadata["user_id"]
    plan_id = payment_intent.metadata["plan_id"]

    if user_id && plan_id do
      attrs = %{
        stripe_customer_id: payment_intent.customer,
        stripe_payment_intent_id: payment_intent.id,
        stripe_charge_id: List.first(payment_intent.charges.data).id,
        purchase_status: :completed,
        amount: payment_intent.amount,
        currency: payment_intent.currency,
        user_id: user_id,
        plan_id: plan_id,
        purchased_at: DateTime.utc_now(),
        metadata: payment_intent.metadata
      }

      case create_purchase(attrs) do
        {:ok, purchase} ->
          Logger.info("Single purchase recorded: #{purchase.id}")
          {:ok, purchase}
        {:error, changeset} ->
          Logger.error("Failed to record single purchase: #{inspect(changeset.errors)}")
          {:error, changeset}
      end
    else
      Logger.error("Missing user_id or plan_id in payment intent metadata")
      {:error, :missing_metadata}
    end
  end

  @doc """
  Counts total completed purchases.
  """
  def count_completed_purchases do
    Purchase
    |> where([p], p.purchase_status == :completed)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Calculates total revenue from single purchases.
  """
  def calculate_single_purchase_revenue do
    Purchase
    |> where([p], p.purchase_status == :completed)
    |> select([p], sum(p.amount))
    |> Repo.one() || 0
  end

  @doc """
  Creates a plan (super admin only).

  ## Parameters
    - attrs: Map of attributes for the new plan
    - actor: The user performing the action (must be super admin)

  ## Returns
    - `{:ok, plan}` on success
    - `{:error, :unauthorized}` if actor is not super admin
    - `{:error, changeset}` on validation failure
  """
  def create_plan(attrs, actor) do
    case actor do
      %User{role: :super_admin} ->
                # Create in Stripe first
        case create_stripe_plan(attrs) do
          {:ok, stripe_data} ->
            # Convert all keys to strings to ensure consistency
            normalized_attrs = normalize_keys_to_strings(attrs)
            normalized_stripe_data = normalize_keys_to_strings(stripe_data)

            # Create in database with Stripe IDs
            plan_attrs = Map.merge(normalized_attrs, normalized_stripe_data)

            %Plan{}
            |> Plan.changeset(plan_attrs)
            |> Repo.insert()
            |> case do
              {:ok, plan} = result ->
                # Broadcast plan creation
                DataSync.broadcast("plans", "all", {:created, %{type: :plan, plan: plan}})

                # Track plan creation
                track_plan_activity(
                  "plan_created",
                  plan,
                  actor,
                  %{
                    "name" => plan.name,
                    "unit_amount" => plan.unit_amount,
                    "currency" => plan.currency,
                    "interval" => plan.interval,
                    "product_type" => plan.product_type,
                    "tier" => plan.metadata["tier"]
                  },
                  %{}
                )

                result
              error ->
                # Clean up Stripe product if database insert fails
                if stripe_data[:stripe_product_id] do
                  Stripe.Product.update(stripe_data[:stripe_product_id], %{active: false})
                end
                error
            end
          error -> error
        end
      _ ->
        {:error, :unauthorized}
    end
  end

  @doc """
  Updates a plan (super admin only).

  ## Parameters
    - plan: The plan to update
    - attrs: Map of attributes to update
    - actor: The user performing the action (must be super admin)

  ## Returns
    - `{:ok, plan}` on success
    - `{:error, :unauthorized}` if actor is not super admin
    - `{:error, changeset}` on validation failure
  """
  def update_plan(%Plan{} = plan, attrs, actor) do
    case actor do
      %User{role: :super_admin} ->
                # Update in Stripe first
        case update_stripe_plan(plan, attrs) do
          {:ok, stripe_data} ->
            # Convert all keys to strings to ensure consistency
            normalized_attrs = normalize_keys_to_strings(attrs)
            normalized_stripe_data = normalize_keys_to_strings(stripe_data)

            # Update in database with any new Stripe data
            plan_attrs = Map.merge(normalized_attrs, normalized_stripe_data)

            plan
            |> Plan.changeset(plan_attrs)
            |> Repo.update()
            |> case do
              {:ok, updated_plan} = result ->
                # Broadcast plan update
                DataSync.broadcast("plans", "all", {:updated, %{type: :plan, plan: updated_plan}})

                # Track plan update with changes
                changes = Map.take(plan_attrs, ["name", "description", "unit_amount", "features", "features_order"])
                |> Enum.reject(fn {_k, v} -> is_nil(v) end)
                |> Enum.into(%{})

                track_plan_activity(
                  "plan_updated",
                  updated_plan,
                  actor,
                  changes,
                  %{
                    "tier" => updated_plan.metadata["tier"],
                    "product_type" => updated_plan.product_type
                  }
                )

                result
              error -> error
            end
          error -> error
        end
      _ ->
        {:error, :unauthorized}
    end
  end

  @doc """
  Deletes a plan (super admin only).

  ## Parameters
    - plan: The plan to delete
    - actor: The user performing the action (must be super admin)

  ## Returns
    - `{:ok, plan}` on success
    - `{:error, :unauthorized}` if actor is not super admin
    - `{:error, changeset}` on constraint violations
  """
  def delete_plan(%Plan{} = plan, actor) do
    case actor do
      %User{role: :super_admin} ->
        # Archive in Stripe first (can't delete if used)
        case archive_stripe_plan(plan) do
          {:ok, _} ->
            Repo.delete(plan)
            |> case do
              {:ok, deleted_plan} = result ->
                # Broadcast plan deletion
                DataSync.broadcast("plans", "all", {:deleted, %{type: :plan, id: deleted_plan.id}})

                # Track plan deletion
                track_plan_activity(
                  "plan_deleted",
                  deleted_plan,
                  actor,
                  %{},
                  %{
                    "name" => deleted_plan.name,
                    "tier" => deleted_plan.metadata["tier"],
                    "product_type" => deleted_plan.product_type,
                    "unit_amount" => deleted_plan.unit_amount
                  }
                )

                result
              error -> error
            end
          error -> error
        end
      _ ->
        {:error, :unauthorized}
    end
  end

  # Platform Settings Management

  @doc """
  Gets a platform setting by key.

  ## Parameters
    - key: The setting key to retrieve

  ## Returns
    - The platform setting if found
    - nil if not found
  """
  def get_platform_setting(key) do
    Repo.get_by(PlatformSetting, key: key)
  end

  @doc """
  Gets the value of a platform setting by key.

  ## Parameters
    - key: The setting key to retrieve
    - default: Default value if setting not found

  ## Returns
    - The boolean value of the setting
    - The default value if setting not found
  """
  def get_platform_setting_value(key, default \\ false) do
    case get_platform_setting(key) do
      nil -> default
      setting -> setting.value
    end
  end

  @doc """
  Updates a platform setting value.

  ## Parameters
    - key: The setting key to update
    - value: The new boolean value
    - actor: The user performing the action (must be super admin)

  ## Returns
    - `{:ok, setting}` on success
    - `{:error, :unauthorized}` if actor is not super admin
    - `{:error, :not_found}` if setting doesn't exist
    - `{:error, changeset}` on validation failure
  """
  def update_platform_setting(key, value, actor) do
    case actor do
      %User{role: :super_admin} ->
        case get_platform_setting(key) do
          nil ->
            {:error, :not_found}
          setting ->
            setting
            |> PlatformSetting.changeset(%{value: value})
            |> Repo.update()
            |> case do
              {:ok, updated_setting} = result ->
                # Broadcast setting update
                DataSync.broadcast("platform_settings", "all",
                  {:updated, %{type: :platform_setting, setting: updated_setting}})
                result
              error -> error
            end
        end
      _ ->
        {:error, :unauthorized}
    end
  end

  @doc """
  Lists all platform settings.

  ## Returns
    - List of all platform settings
  """
  def list_platform_settings do
    PlatformSetting
    |> order_by([s], asc: s.key)
    |> Repo.all()
  end

  @doc """
  Checks if subscriptions are enabled.

  ## Returns
    - true if subscriptions are enabled
    - false otherwise
  """
  def subscriptions_enabled? do
    get_platform_setting_value("subscriptions_enabled", true)
  end

  @doc """
  Checks if single purchases are enabled.

  ## Returns
    - true if single purchases are enabled
    - false otherwise
  """
  def single_purchases_enabled? do
    get_platform_setting_value("single_purchases_enabled", false)
  end

  # Private helper functions for Stripe integration

    defp create_stripe_plan(attrs) do
    name = attrs[:name] || attrs["name"]
    product_type = attrs[:product_type] || attrs["product_type"]
    description = attrs[:description] || attrs["description"] || ""
    metadata = attrs[:metadata] || attrs["metadata"] || %{}

    Logger.info("Creating Stripe plan: #{name} (#{product_type})")

    # Create Stripe product
    case Stripe.Product.create(%{
      name: name,
      description: description,
      metadata: metadata
    }) do
      {:ok, product} ->
        Logger.info("Stripe product created: #{product.id}")

        # Create Stripe price based on product type
        case product_type do
          :subscription ->
            create_stripe_subscription_price(product.id, attrs)
          :single_purchase ->
            create_stripe_one_time_price(product.id, attrs)
          "subscription" ->
            create_stripe_subscription_price(product.id, attrs)
          "single_purchase" ->
            create_stripe_one_time_price(product.id, attrs)
          _ ->
            {:error, "Invalid product type"}
        end
      {:error, error} ->
        Logger.error("Failed to create Stripe product: #{inspect(error)}")
        {:error, error}
    end
  end

  defp create_stripe_subscription_price(product_id, attrs) do
    unit_amount = attrs[:unit_amount] || attrs["unit_amount"]
    currency = attrs[:currency] || attrs["currency"]
    interval = attrs[:interval] || attrs["interval"]

    case Stripe.Price.create(%{
      unit_amount: unit_amount,
      currency: currency,
      product: product_id,
      recurring: %{interval: interval}
    }) do
      {:ok, price} ->
        {:ok, %{
          stripe_product_id: product_id,
          stripe_price_id: price.id
        }}
      {:error, error} ->
        # Clean up product if price creation fails
        Stripe.Product.update(product_id, %{active: false})
        {:error, error}
    end
  end

  defp create_stripe_one_time_price(product_id, attrs) do
    unit_amount = attrs[:unit_amount] || attrs["unit_amount"]
    currency = attrs[:currency] || attrs["currency"]

    case Stripe.Price.create(%{
      unit_amount: unit_amount,
      currency: currency,
      product: product_id
      # No recurring field for one-time payments
    }) do
      {:ok, price} ->
        {:ok, %{
          stripe_product_id: product_id,
          stripe_price_id: price.id
        }}
      {:error, error} ->
        # Clean up product if price creation fails
        Stripe.Product.update(product_id, %{active: false})
        {:error, error}
    end
  end

      defp update_stripe_plan(plan, attrs) do
    name = attrs[:name] || attrs["name"] || plan.name
    description = attrs[:description] || attrs["description"] || plan.description
    metadata = attrs[:metadata] || attrs["metadata"] || plan.metadata

    Logger.info("Updating Stripe plan: #{plan.name} (#{plan.stripe_product_id})")

    # Update Stripe product
    case Stripe.Product.update(plan.stripe_product_id, %{
      name: name,
      description: description,
      metadata: metadata
    }) do
      {:ok, _product} ->
        Logger.info("Stripe product updated: #{plan.stripe_product_id}")

        # For price updates, we need to create a new price since Stripe prices are immutable
        # Only create new price if unit_amount, currency, or interval changed
        needs_new_price = price_attributes_changed?(plan, attrs)

        if needs_new_price do
          Logger.info("Price attributes changed, creating new Stripe price")
          create_new_stripe_price(plan, attrs)
        else
          Logger.info("No price changes needed")
          {:ok, %{}}
        end
      {:error, error} ->
        Logger.error("Failed to update Stripe product: #{inspect(error)}")
        {:error, error}
    end
  end

  defp price_attributes_changed?(plan, attrs) do
    unit_amount = attrs[:unit_amount] || attrs["unit_amount"]
    currency = attrs[:currency] || attrs["currency"]
    interval = attrs[:interval] || attrs["interval"]

    (unit_amount && unit_amount != plan.unit_amount) ||
    (currency && currency != plan.currency) ||
    (interval && interval != plan.interval)
  end

    defp create_new_stripe_price(plan, attrs) do
    Logger.info("Archiving old Stripe price: #{plan.stripe_price_id}")

    # Archive the old price
    case Stripe.Price.update(plan.stripe_price_id, %{active: false}) do
      {:ok, _} ->
        Logger.info("Old price archived, creating new price")

        # Create new price with updated attributes
        unit_amount = attrs[:unit_amount] || attrs["unit_amount"] || plan.unit_amount
        currency = attrs[:currency] || attrs["currency"] || plan.currency
        interval = attrs[:interval] || attrs["interval"] || plan.interval

        price_params = %{
          unit_amount: unit_amount,
          currency: currency,
          product: plan.stripe_product_id
        }

        # Add recurring if it's a subscription
        price_params = if plan.product_type == :subscription and interval do
          Map.put(price_params, :recurring, %{interval: interval})
        else
          price_params
        end

        Logger.info("Creating new Stripe price with params: #{inspect(price_params)}")

        case Stripe.Price.create(price_params) do
          {:ok, new_price} ->
            Logger.info("New Stripe price created: #{new_price.id}")
            {:ok, %{stripe_price_id: new_price.id}}
          {:error, error} ->
            Logger.error("Failed to create new Stripe price: #{inspect(error)}")
            {:error, error}
        end
      {:error, error} ->
        Logger.error("Failed to archive old Stripe price: #{inspect(error)}")
        {:error, error}
    end
  end

  defp archive_stripe_plan(plan) do
    # Archive Stripe product (this also archives associated prices)
    case Stripe.Product.update(plan.stripe_product_id, %{active: false}) do
      {:ok, _product} ->
        {:ok, :archived}
      {:error, error} ->
        {:error, error}
    end
  end



  # Helper function to normalize all keys in a map to strings
  defp normalize_keys_to_strings(map) when is_map(map) do
    map
    |> Enum.map(fn
      {k, v} when is_map(v) -> {to_string(k), normalize_keys_to_strings(v)}
      {k, v} -> {to_string(k), v}
    end)
    |> Enum.into(%{})
  end
  defp normalize_keys_to_strings(value), do: value

  @doc """
  Checks if a user can create a new company based on their subscription plan.

  ## Parameters
    - user: The user to check

  ## Returns
    - `true` if the user can create a new company
    - `false` if the user has reached their company limit
  """
  def can_create_company?(%User{} = user) do
    limit = get_company_limit_for_user(user)
    current_count = Companies.count_companies_by_owner(user.id)

    case limit do
      :unlimited -> true
      limit when is_integer(limit) -> current_count < limit
      _ -> false
    end
  end

  @doc """
  Gets the company creation limit for a user based on their subscription.

  ## Parameters
    - user: The user whose company limit to retrieve

  ## Returns
    - The company limit as an integer
    - `:unlimited` if there is no limit
  """
  def get_company_limit_for_user(%User{} = user) do
    # Super admins have unlimited access
    if user.role == :super_admin do
      :unlimited
    else
      case get_user_subscription(user.id) do
        nil ->
          # Default limit for users without a subscription (e.g., free plan)
          # You might want to make this configurable
          1

        %Subscription{plan: %Plan{features: features}} ->
          # "projects" is used for companies in the plan features
          case Map.get(features, "projects", "0") do
            "Unlimited" ->
              :unlimited
            limit when is_integer(limit) ->
              limit
            limit_str when is_binary(limit_str) ->
              case Integer.parse(limit_str) do
                {limit, ""} -> limit
                _ -> 0 # Default to 0 if parsing fails
              end
            _ ->
              0 # Default for any other type
          end
        _ -> 0
      end
    end
  end
end

defmodule Core.Tasks.Seeder do
  @moduledoc """
  Simple production-safe database seeding with direct DB calls.
  """

  require Logger

  alias Core.Repo
  alias Core.Accounts.{User, Profile}
  alias Core.Subscriptions.{Plan}
  alias Core.AI.{Prompt}
  alias Core.Blog.Post
  alias Core.FeatureRequests.FeatureRequest

  @doc """
  Create essential test data directly with database calls.
  Safe for production - only creates data that doesn't exist.
  """
  def create_essential_data do
    Logger.info("🌱 Creating essential test data...")
    start_time = System.monotonic_time(:millisecond)

    try do
      # Show current database state for debugging
      debug_current_state()

      # Fix schema first
      fix_schema()

      # Create data
      create_subscription_plans()
      create_single_purchase_products()
      create_test_users()
      create_ai_prompts()
      create_blog_posts()
      create_feature_requests()

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      Logger.info("🎉 Essential data creation completed in #{duration}ms")
      {:ok, :completed}
    rescue
      error ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        Logger.error("❌ Data creation failed after #{duration}ms: #{inspect(error)}")
        {:error, error}
    end
  end

  # Debug function to show current database state
  defp debug_current_state do
    Logger.info("🔍 Current database state:")

    import Ecto.Query

    # Count users by role
    user_counts = Repo.all(
      from u in User,
      group_by: u.role,
      select: {u.role, count(u.id)}
    )

    if Enum.empty?(user_counts) do
      Logger.info("  👥 No users found in database")
    else
      Enum.each(user_counts, fn {role, count} ->
        Logger.info("  👥 #{count} #{role} user(s)")
      end)
    end

    # Count plans
    plan_count = Repo.aggregate(Plan, :count, :id)
    Logger.info("  📋 #{plan_count} plan(s)")

    # Count prompts
    prompt_count = Repo.aggregate(Prompt, :count, :id)
    Logger.info("  🤖 #{prompt_count} AI prompt(s)")

    # Count blog posts
    post_count = Repo.aggregate(Post, :count, :id)
    Logger.info("  📝 #{post_count} blog post(s)")
  end

  # Fix database schema issues
  defp fix_schema do
    Logger.info("🔧 Checking database schema...")

    try do
      Repo.query!("SELECT product_type FROM plans LIMIT 1")
      Logger.info("✅ Schema looks good")
    rescue
      Postgrex.Error ->
        Logger.info("🔧 Adding missing product_type column...")
        Repo.query!("ALTER TABLE plans ADD COLUMN IF NOT EXISTS product_type VARCHAR(255) DEFAULT 'subscription'")
        Logger.info("✅ Schema fixed")
    end
  end

  # Create subscription plans
  defp create_subscription_plans do
    Logger.info("📋 Creating subscription plans...")

    plans = [
      %{name: "Small Plan", amount: 1500, tier: "small"},
      %{name: "Medium Plan", amount: 3000, tier: "medium"},
      %{name: "Large Plan", amount: 5000, tier: "large"}
    ]

    Enum.each(plans, fn plan_data ->
      if !Repo.get_by(Plan, name: plan_data.name) do
        Logger.info("➕ Creating plan: #{plan_data.name}")

        # Create Stripe product and prices
        create_stripe_plan(plan_data)

        Process.sleep(1000) # Small delay between Stripe calls
      else
        Logger.info("⏭️  Plan '#{plan_data.name}' already exists")
      end
    end)
  end

  # Create single purchase products
  defp create_single_purchase_products do
    Logger.info("🛒 Creating single purchase products...")

    products = [
      %{name: "Premium Template Pack", amount: 4999},
      %{name: "Advanced Analytics Report", amount: 9999}
    ]

    Enum.each(products, fn product_data ->
      if !Repo.get_by(Plan, name: product_data.name) do
        Logger.info("➕ Creating product: #{product_data.name}")

        # Create Stripe product
        create_stripe_product(product_data)

        Process.sleep(1000)
      else
        Logger.info("⏭️  Product '#{product_data.name}' already exists")
      end
    end)
  end

  # Create test users
  defp create_test_users do
    Logger.info("👥 Creating test users...")

    users = [
      %{email: "admin@example.com", role: :admin, first_name: "Admin", last_name: "User"},
      %{email: "user@example.com", role: :basic, first_name: "Test", last_name: "User"}
    ]

    Enum.each(users, fn user_data ->
      if !Repo.get_by(User, email: user_data.email) do
        Logger.info("➕ Creating user: #{user_data.email}")

        {:ok, user} = %User{}
        |> User.registration_changeset(%{
          email: user_data.email,
          password: "password1234",
          role: user_data.role,
          onboarding_completed: true
        })
        |> Repo.insert()

        # Create profile
        Repo.insert!(%Profile{
          first_name: user_data.first_name,
          last_name: user_data.last_name,
          bio: "Test user created by seeding",
          user_id: user.id
        })
      else
        Logger.info("⏭️  User '#{user_data.email}' already exists")
      end
    end)
  end

  # Create AI prompts
  defp create_ai_prompts do
    Logger.info("🤖 Creating AI prompts...")

    # Get the first super admin (in case there are multiple)
    import Ecto.Query

    # Check how many super admins exist for debugging
    super_admin_count = Repo.aggregate(from(u in User, where: u.role == :super_admin), :count, :id)
    Logger.info("🔍 Found #{super_admin_count} super admin(s) in database")

    super_admin = Repo.one(from u in User, where: u.role == :super_admin, limit: 1)

    if super_admin do
      Logger.info("✅ Using super admin: #{super_admin.email}")

      prompts = [
        %{name: "System Prompt", category: "system", content: "You are a helpful AI assistant."},
        %{name: "Customer Support", category: "customer_support", content: "Resolve customer issues efficiently."}
      ]

      Enum.each(prompts, fn prompt_data ->
        if !Repo.get_by(Prompt, name: prompt_data.name) do
          Logger.info("➕ Creating prompt: #{prompt_data.name}")

          Repo.insert!(%Prompt{
            name: prompt_data.name,
            description: "Test prompt created by seeding",
            content: prompt_data.content,
            category: prompt_data.category,
            is_active: true,
            created_by: super_admin.id
          })
        else
          Logger.info("⏭️  Prompt '#{prompt_data.name}' already exists")
        end
      end)
    else
      Logger.info("⚠️  No super admin found, skipping prompts")
    end
  end

  # Create blog posts
  defp create_blog_posts do
    Logger.info("📝 Creating blog posts...")

    posts = [
      %{title: "Getting Started with Phoenix LiveView", published: :published},
      %{title: "Building Scalable Web Applications", published: :draft}
    ]

    Enum.each(posts, fn post_data ->
      if !Repo.get_by(Post, title: post_data.title) do
        Logger.info("➕ Creating blog post: #{post_data.title}")

        %Post{}
        |> Post.changeset(%{
          title: post_data.title,
          description: "Test blog post created by seeding",
          content: "This is a test blog post with sample content...",
          published: post_data.published,
          meta: %{"author" => "System", "tags" => ["tutorial"]}
        })
        |> Repo.insert!()
      else
        Logger.info("⏭️  Blog post '#{post_data.title}' already exists")
      end
    end)
  end

  # Create feature requests
  defp create_feature_requests do
    Logger.info("💡 Creating feature requests...")

    # Get the first basic user (in case there are multiple)
    import Ecto.Query

    basic_user_count = Repo.aggregate(from(u in User, where: u.role == :basic), :count, :id)
    Logger.info("🔍 Found #{basic_user_count} basic user(s) in database")

    basic_user = Repo.one(from u in User, where: u.role == :basic, limit: 1)

    if basic_user do
      Logger.info("✅ Using basic user: #{basic_user.email}")

      requests = [
        "Add dark mode support to the dashboard",
        "Implement two-factor authentication"
      ]

      Enum.each(requests, fn description ->
        if !Repo.get_by(FeatureRequest, feature_description: description) do
          Logger.info("➕ Creating feature request")

          Repo.insert!(%FeatureRequest{
            feature_description: description,
            priority_rating: 8,
            feasibility_rating: 1,
            user_id: basic_user.id
          })
        else
          Logger.info("⏭️  Similar feature request already exists")
        end
      end)
    else
      Logger.info("⚠️  No basic user found, skipping feature requests")
    end
  end

  # Create Stripe plan with monthly and yearly variants
  defp create_stripe_plan(plan_data) do
    try do
      # Create Stripe product
      {:ok, product} = Stripe.Product.create(%{
        name: plan_data.name,
        description: "#{plan_data.name} subscription",
        metadata: %{tier: plan_data.tier}
      })

      # Create monthly price
      {:ok, monthly_price} = Stripe.Price.create(%{
        unit_amount: plan_data.amount,
        currency: "usd",
        product: product.id,
        recurring: %{interval: "month"}
      })

      # Create yearly price
      {:ok, yearly_price} = Stripe.Price.create(%{
        unit_amount: plan_data.amount * 10,
        currency: "usd",
        product: product.id,
        recurring: %{interval: "year"}
      })

      # Store monthly plan in database
      Repo.insert!(%Plan{
        name: plan_data.name,
        description: "#{plan_data.name} subscription",
        unit_amount: plan_data.amount,
        currency: "usd",
        interval: "month",
        product_type: :subscription,
        metadata: %{tier: plan_data.tier},
        features: %{"projects" => 5, "storage" => "5GB"},
        features_order: ["projects", "storage"],
        stripe_price_id: monthly_price.id,
        stripe_product_id: product.id
      })

      # Store yearly plan in database
      Repo.insert!(%Plan{
        name: plan_data.name <> " (Yearly)",
        description: "#{plan_data.name} yearly subscription",
        unit_amount: plan_data.amount * 10,
        currency: "usd",
        interval: "year",
        product_type: :subscription,
        metadata: %{tier: plan_data.tier},
        features: %{"projects" => 5, "storage" => "5GB"},
        features_order: ["projects", "storage"],
        stripe_price_id: yearly_price.id,
        stripe_product_id: product.id
      })

      Logger.info("✅ Created Stripe plan: #{plan_data.name}")
    rescue
      error ->
        Logger.error("❌ Failed to create Stripe plan #{plan_data.name}: #{inspect(error)}")
    end
  end

  # Create Stripe single purchase product
  defp create_stripe_product(product_data) do
    try do
      # Create Stripe product
      {:ok, stripe_product} = Stripe.Product.create(%{
        name: product_data.name,
        description: "Single purchase product",
        metadata: %{product_type: "single_purchase"}
      })

      # Create price
      {:ok, stripe_price} = Stripe.Price.create(%{
        unit_amount: product_data.amount,
        currency: "usd",
        product: stripe_product.id
      })

      # Store in database
      Repo.insert!(%Plan{
        name: product_data.name,
        description: "Single purchase product",
        unit_amount: product_data.amount,
        currency: "usd",
        interval: nil,
        product_type: :single_purchase,
        metadata: %{product_type: "single_purchase"},
        features: %{"feature_1" => "Premium Content"},
        features_order: ["feature_1"],
        stripe_price_id: stripe_price.id,
        stripe_product_id: stripe_product.id
      })

      Logger.info("✅ Created Stripe product: #{product_data.name}")
    rescue
      error ->
        Logger.error("❌ Failed to create Stripe product #{product_data.name}: #{inspect(error)}")
    end
  end
end

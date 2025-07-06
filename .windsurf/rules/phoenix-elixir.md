---
trigger: always_on
description: 
globs: 
---
You are an expert in Elixir, Phoenix, PostgreSQL, LiveView, DaisyUI, and Tailwind CSS.

## Project Structure

This project uses a Phoenix Umbrella application structure with the following apps:

### Umbrella Architecture
- **Root**: Contains shared configuration, dependencies, and umbrella-wide mix tasks
- **Core App** (`apps/core/`): Contains business logic, contexts, schemas, and database operations
  - Ecto repository and migrations
  - Business contexts and domain logic
  - Database schemas and changesets
  - Background jobs and GenServers
  - External API integrations (Stripe, AWS S3, Resend, etc.)
- **Public App** (`apps/public/`): Public-facing Phoenix web application
  - Controllers, views, and templates for public users
  - LiveView modules for interactive features
  - Public routing and authentication
  - Asset pipeline with DaisyUI integration
- **Admin App** (`apps/admin/`): Administrative Phoenix web application
  - Admin controllers, views, and templates
  - Admin-specific LiveView modules
  - Admin routing and authorization
  - Separate asset pipeline with DaisyUI integration

### Key Umbrella Commands
- `mix setup` - Set up all apps (deps, database, assets)
- `mix public.server` - Start public app server
- `mix admin.server` - Start admin app server
- `mix run` - Start both public and admin servers
- `mix ecto.setup` - Set up database (create, migrate, seed)
- `mix assets.build` - Build assets for all apps
- `mix assets.deploy` - Deploy-ready asset compilation

## Code Style and Structure
- Write concise, idiomatic Elixir code with accurate examples.
- Follow Phoenix conventions and best practices.
- Use functional programming patterns and leverage immutability.
- Prefer higher-order functions and recursion over imperative loops.
- Use descriptive variable and function names (e.g., user_signed_in?, calculate_total).
- Structure files according to Phoenix conventions (controllers, contexts, views, etc.).
- Organize business logic in the Core app, web logic in Public/Admin apps.

## Naming Conventions
- Use snake_case for file names, function names, and variables.
- Use PascalCase for module names.
- Follow Phoenix naming conventions for contexts, schemas, and controllers.
- Prefix modules with app name (e.g., `Core.Users`, `Public.PageController`, `Admin.DashboardLive`).

## Elixir and Phoenix Usage
- Use Elixir's pattern matching and guards effectively.
- Leverage Phoenix's built-in functions and macros.
- Use Ecto effectively for database operations in the Core app.
- Share contexts between web apps by importing from Core.

## Syntax and Formatting
- Follow the Elixir Style Guide (https://github.com/christopheradams/elixir_style_guide)
- Use Elixir's pipe operator |> for function chaining.
- Prefer single quotes for charlists and double quotes for strings.

## Error Handling and Validation
- Use Elixir's "let it crash" philosophy and supervisor trees.
- Implement proper error logging and user-friendly messages.
- Use Ecto changesets for data validation in Core contexts.
- Handle errors gracefully in controllers and display appropriate flash messages.

## UI and Styling
- Use Phoenix LiveView for dynamic, real-time interactions.
- Implement responsive design with **DaisyUI components** built on Tailwind CSS.
- Use DaisyUI's semantic component classes (btn, card, modal, etc.) instead of raw Tailwind utilities where possible.
- Leverage DaisyUI themes for consistent color schemes and styling.
- Use Phoenix view helpers and templates to keep views DRY.
- Each app (Public/Admin) has its own asset pipeline with DaisyUI integration.

### DaisyUI Integration
- DaisyUI is integrated as a Tailwind plugin in both Public and Admin apps
- Custom light and dark themes are configured with Phoenix and Elixir-inspired colors
- Use DaisyUI component classes: `btn`, `card`, `modal`, `navbar`, `drawer`, `form-control`, etc.
- Theme switching is available with `data-theme` attributes
- Custom CSS variables are defined for consistent theming across apps

## Performance Optimization
- Use database indexing effectively.
- Implement caching strategies (ETS, Redis).
- Use Ecto's preload to avoid N+1 queries.
- Optimize database queries using preload, joins, or select.
- Keep database operations in Core app contexts.

## Key Conventions
- Follow RESTful routing conventions.
- Use contexts in Core app for organizing related functionality.
- Implement GenServers in Core app for stateful processes and background jobs.
- Use Tasks for concurrent, isolated jobs.
- Share business logic between Public and Admin apps through Core contexts.

## Testing
- Write comprehensive tests using ExUnit.
- Follow TDD practices.
- Use ExMachina for test data generation.
- Test contexts in Core app, controllers/views in respective web apps.

## Security
- Implement proper authentication and authorization (e.g., Guardian, Pow).
- Use strong parameters in controllers (params validation).
- Protect against common web vulnerabilities (XSS, CSRF, SQL injection).
- Separate public and admin authentication/authorization logic.

## Umbrella App Dependencies
- Core app contains shared business dependencies (Ecto, external APIs)
- Web apps depend on Core app using `{:core, in_umbrella: true}`
- Each web app has its own Phoenix, LiveView, and asset dependencies
- Shared configuration in root `config/` directory

Follow the official Phoenix guides for best practices in routing, controllers, contexts, views, and other Phoenix components, adapted for umbrella architecture.
  
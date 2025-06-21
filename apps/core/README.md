# Core

The Core application serves as the foundational layer of the PhxplateUmbrella project, containing all business logic, data models, and shared services that power the entire platform.

## Purpose

Core acts as the central nervous system of the platform, providing:
- **Business Logic**: All domain-specific logic and rules
- **Data Layer**: Database schemas, migrations, and data access patterns
- **Shared Services**: Common functionality used across all applications
- **Context Boundaries**: Clear separation of business domains

## Key Responsibilities

### Business Contexts

- **Accounts Context**: User management, authentication, and authorization
- **Companies Context**: Company creation, management, and employee relationships
- **Subscriptions Context**: Stripe integration, billing, and plan management
- **AI Context**: Anthropic Claude integration and conversation management
- **Chat Context**: Live support chat system and messaging
- **Blog Context**: Content management and publishing
- **Bookmarks Context**: User bookmarking system for companies
- **Feature Requests Context**: User feedback and feature request management

### Data Management

- **Ecto Schemas**: All database table definitions and relationships
- **Migrations**: Database structure evolution and data transformations
- **Changesets**: Data validation and transformation logic
- **Queries**: Optimized database queries and aggregations

### External Integrations

- **Stripe API**: Payment processing and subscription management
- **Anthropic API**: AI chat capabilities and conversation handling
- **AWS S3**: File storage and asset management
- **Resend API**: Email delivery and notification system

### Shared Utilities

- **PubSub**: Real-time event broadcasting across applications
- **Tracking**: User activity and analytics collection
- **Authorization**: Role-based access control and permissions
- **Tasks**: Background job processing and scheduled tasks

## Architecture Patterns

### Context-Driven Design
Each business domain is organized into contexts with clear boundaries:
```elixir
# Example context structure
Phxplate.Accounts
├── User schema
├── UserToken schema  
├── User context functions
└── Authentication logic

Phxplate.Companies
├── Company schema
├── Employee schema
├── Company context functions
└── Invitation logic
```

### Service Layer Pattern
Complex operations are encapsulated in service modules:
- `Phxplate.AI` - AI conversation management
- `Phxplate.Subscriptions` - Billing and plan management
- `Phxplate.PubSub` - Event broadcasting
- `Phxplate.Tracking` - Activity tracking

### Repository Pattern
Data access is centralized through context modules that act as repositories, providing a clean interface between business logic and data persistence.

## Key Features Implemented

### User Management System
- Multi-role user system (Basic, Admin, Super Admin)
- Secure authentication with password hashing
- Email confirmation and password reset flows
- User profile management with avatar uploads

### Subscription & Billing
- Integration with Stripe for payment processing
- Support for monthly and yearly billing cycles
- Multiple subscription tiers with feature limitations
- Automatic plan upgrades and downgrades

### AI Integration
- Multiple Claude model support (Haiku, Sonnet, Opus variants)
- Streaming conversation capabilities
- Persistent conversation history
- Auto-generated conversation titles

### Company Management
- Multi-tenant company system
- Employee invitation and management
- Role-based permissions within companies
- Public company directory with bookmarking

### Live Chat Support
- Real-time messaging with WebSocket support
- Offline message handling with email notifications
- Device information collection for troubleshooting
- Session management and transcript generation

## Installation

Add `core` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:core, in_umbrella: true}
  ]
end
```

## Configuration

The Core app requires several environment variables for external service integration:

```elixir
# config/config.exs
config :core,
  stripe_secret_key: System.get_env("STRIPE_SECRET_KEY"),
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  resend_api_key: System.get_env("RESEND_API_KEY")
```

## Database Setup

Run migrations to set up the database schema:

```bash
mix ecto.migrate
```

Seed the database with initial data:

```bash
mix run priv/repo/seeds.exs
```

## Testing

The Core application includes comprehensive tests for all business logic:

```bash
mix test
```

## Usage Examples

### User Management
```elixir
# Create a new user
{:ok, user} = Phxplate.Accounts.register_user(%{
  email: "user@example.com",
  password: "secure_password"
})

# Authenticate user
{:ok, user} = Phxplate.Accounts.get_user_by_email_and_password(
  "user@example.com", 
  "secure_password"
)
```

### AI Integration
```elixir
# Start an AI conversation
{:ok, conversation} = Phxplate.AI.create_conversation(
  user_id, 
  "Help me with Elixir", 
  "claude-3-sonnet-20240229"
)

# Send a message
{:ok, response} = Phxplate.AI.chat_conversation(
  conversation.id, 
  "What are GenServers?", 
  user_id
)
```

### Company Management
```elixir
# Create a company
{:ok, company} = Phxplate.Companies.create_company(admin_user, %{
  name: "Acme Corp",
  description: "Software company"
})

# Invite an employee
{:ok, invitation} = Phxplate.Companies.invite_employee(
  company, 
  "employee@example.com", 
  admin_user
)
```

## Contributing

When adding new features to Core:

1. **Follow Context Boundaries**: Add new functionality to appropriate contexts
2. **Write Tests**: All business logic should have comprehensive test coverage  
3. **Document APIs**: Public functions should have clear documentation
4. **Use Changesets**: All data validation should go through Ecto changesets
5. **Consider Performance**: Optimize database queries and avoid N+1 problems

The Core application is the foundation that enables all other applications in the umbrella to function effectively. Changes here impact the entire system, so careful consideration and testing are essential.


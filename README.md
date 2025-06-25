# Umbrella

A comprehensive Phoenix umbrella application designed for building scalable, multi-tenant SaaS platforms with advanced features including AI integration, subscription management, and administrative capabilities.

## Project Structure

This umbrella project is organized into four main applications, each serving a specific purpose in the overall architecture:

```
umbrella/
├── apps/
│   ├── core/       # Business logic and shared modules
│   ├── public/     # Public-facing application
│   ├── admin/      # Administrative interface
├── config/         # Shared configuration
└── deps/           # Shared dependencies
```

## Applications Overview

### Core (`apps/core/`)
The foundation of the platform containing:
- Business logic and domain models
- Database schemas and migrations  
- Shared contexts and services
- AI integration services
- Subscription and payment processing
- User authentication and authorization

### Web (`apps/public/`)
The main public-facing application featuring:
- User registration and authentication
- Company management and directory
- Live chat support system
- Blog and content management
- Subscription management interface
- Public API endpoints

### Admin (`apps/admin/`)
Administrative interface providing:
- Super admin dashboard
- User and company management
- Subscription and billing oversight
- AI chat interface for testing
- Platform analytics and reporting
- Support ticket management

## Key Features

- **Multi-tenant Architecture**: Scalable design supporting multiple companies and users
- **AI Integration**: Powered by Anthropic's Claude models for intelligent assistance
- **Subscription Management**: Integrated with Stripe for billing and plan management
- **Live Chat Support**: Real-time customer support with offline capabilities
- **Role-based Access Control**: Granular permissions for users, admins, and super admins
- **Content Management**: Blog system and dynamic content management
- **Company Directory**: Public company listings with bookmarking features

## Development Setup

1. Install dependencies:
   ```bash
   mix deps.get
   ```

2. Set up environment variables:
   ```bash
   cp exports.dev.sh exports.sh
   # Edit exports.sh with your configuration
   source exports.sh
   ```

3. Create and migrate the database:
   ```bash
   mix ecto.setup
   ```

4. Start the development server:
   ```bash
   mix run 
   or 
   mix public.server
   mix admin.server
   ```

## Architecture Benefits

The umbrella structure provides several advantages:

- **Separation of Concerns**: Each app has a clear, focused responsibility
- **Shared Dependencies**: Common libraries are managed at the umbrella level
- **Independent Deployment**: Apps can be deployed and scaled independently
- **Code Reusability**: Shared logic in Core, shared UI components in UI
- **Team Collaboration**: Different teams can work on different apps simultaneously

## Getting Started

Visit the individual app READMEs for specific setup instructions:
- [Core Application](apps/core/README.md)
- [Public Application](apps/public/README.md) 
- [Admin Application](apps/admin/README.md)

# Public

The application serves as the main public-facing interface of the Umbrella project, providing user registration, company management, live chat support, and subscription services to end users.

## Purpose

The Public app is the primary customer-facing application that delivers:
- **User Experience**: Intuitive interface for all user interactions
- **Public Services**: Company directory, blog, and informational pages
- **Customer Support**: Live chat system with real-time messaging
- **Subscription Management**: Self-service billing and plan management
- **Company Operations**: Multi-tenant company management features

## Key Features

### User Authentication & Management
- **Registration & Login**: Secure user onboarding with email verification
- **Profile Management**: User profile editing with avatar uploads
- **Password Management**: Secure password reset and change functionality
- **Role-based Access**: Different interfaces for Basic users, Admins, and Super Admins

### Company Management System
- **Company Creation**: Admin users can create and manage companies
- **Employee Management**: Invite and manage team members with role-based permissions
- **Company Directory**: Public browsable directory of all companies
- **Bookmarking System**: Users can bookmark and track favorite companies
- **Company Profiles**: Rich company pages with descriptions, logos, and details

### Live Chat Support
- **Real-time Messaging**: WebSocket-based live chat with support agents
- **Anonymous & Authenticated Chat**: Support for both logged-in and guest users
- **Offline Support**: Message queuing when support agents are unavailable
- **Device Information**: Automatic collection of troubleshooting data
- **Session Management**: Persistent chat sessions with full message history
- **Email Notifications**: Automatic notifications for offline support requests

### Subscription & Billing
- **Plan Selection**: Choose from Small, Medium, or Large subscription tiers
- **Stripe Integration**: Secure payment processing with monthly/yearly options
- **Self-service Management**: Users can upgrade, downgrade, or cancel subscriptions
- **Billing History**: Access to invoices and payment history
- **Feature Limitations**: Plan-based feature access and restrictions

### Content Management
- **Blog System**: Public blog with rich content and categorization
- **Static Pages**: About, Pricing, Contact, and other informational pages
- **Contact Forms**: Integrated contact forms with email notifications
- **SEO Optimization**: Meta tags, structured data, and search-friendly URLs

### Public API
- **REST Endpoints**: Public API for company data and basic operations
- **Authentication**: API key-based authentication for external integrations
- **Rate Limiting**: Built-in protection against API abuse
- **Documentation**: Comprehensive API documentation and examples

## Architecture

### Phoenix LiveView
The application leverages Phoenix LiveView for real-time, interactive user experiences:
- **Real-time Updates**: Live updates without page refreshes
- **Server-side Rendering**: Fast initial page loads with progressive enhancement
- **WebSocket Communication**: Efficient real-time data synchronization
- **Form Handling**: Rich form interactions with live validation

### Component Structure
```
lib/public/
├── controllers/          # HTTP request handling
├── live/                # LiveView modules
│   ├── dashboard/       # User dashboard features
│   ├── company/         # Company management
│   ├── chat/           # Live chat interface
│   └── subscription/   # Billing management
├── components/         # Reusable UI components
├── channels/          # WebSocket channels
└── templates/         # HTML templates
```

### Authentication & Authorization
- **Plug-based Authentication**: Secure session management
- **Role-based Authorization**: Different access levels per user type
- **CSRF Protection**: Built-in security against cross-site attacks
- **Session Management**: Secure session handling with automatic cleanup

## User Flows

### New User Journey
1. **Discovery**: Browse public company directory and blog content
2. **Registration**: Create account with email verification
3. **Onboarding**: Complete profile setup and explore features
4. **Subscription**: Choose and activate a subscription plan
5. **Company Management**: Create or join companies as appropriate

### Support Experience
1. **Chat Initiation**: Start chat from any page (anonymous or authenticated)
2. **Real-time Support**: Live messaging with support agents
3. **Offline Handling**: Leave messages when support is unavailable
4. **Resolution**: Receive help and optional email transcript

### Admin Workflow
1. **Company Creation**: Set up new company with details and branding
2. **Team Building**: Invite employees via email invitations
3. **Management**: Oversee company operations and employee access
4. **Growth**: Upgrade subscription plans as company scales

## Technical Features

### Performance Optimizations
- **Asset Pipeline**: Optimized CSS and JavaScript bundling
- **Image Processing**: Automatic image optimization and resizing
- **Caching**: Strategic caching of frequently accessed data
- **Database Optimization**: Efficient queries with proper indexing

### Security Features
- **Input Validation**: Comprehensive input sanitization and validation
- **XSS Protection**: Built-in cross-site scripting prevention
- **SQL Injection Prevention**: Parameterized queries via Ecto
- **Rate Limiting**: Protection against abuse and DDoS attacks

### Monitoring & Analytics
- **Error Tracking**: Comprehensive error logging and monitoring
- **Performance Metrics**: Application performance tracking
- **User Analytics**: User behavior and engagement tracking
- **Health Checks**: System health monitoring and alerting

## Development Setup

1. **Install Dependencies**:
   ```bash
   cd apps/public
   mix deps.get
   ```

2. **Set Up Database** (from umbrella root):
   ```bash
   mix ecto.setup
   ```

3. **Configure Environment Variables**:
   ```bash
   # Required for full functionality
   export STRIPE_PUBLISHABLE_KEY="pk_test_..."
   export RESEND_API_KEY="re_..."
   export S3_BUCKET="your-bucket"
   ```

4. **Start Development Server**:
   ```bash
   mix phx.server
   ```

Visit [`localhost:4000`](http://localhost:4000) to access the application.

## Testing

Run the test suite:
```bash
mix test
```

Run tests with coverage:
```bash
mix test --cover
```

## Deployment

The Web application is designed for production deployment with:

### Environment Configuration
- **Production Secrets**: Secure environment variable management
- **SSL/TLS**: HTTPS enforcement and security headers
- **Asset Compilation**: Optimized asset builds for production

### Scaling Considerations
- **Database Connection Pooling**: Efficient database connection management
- **Session Storage**: Distributed session storage for multi-instance deployments
- **File Uploads**: S3 integration for scalable file storage
- **CDN Integration**: Static asset delivery via CDN

## Contributing

When contributing to the Web application:

1. **Follow Phoenix Conventions**: Use standard Phoenix patterns and conventions
2. **LiveView Best Practices**: Leverage LiveView for interactive features
3. **Responsive Design**: Ensure all interfaces work on mobile and desktop
4. **Accessibility**: Follow WCAG guidelines for accessible interfaces
5. **Testing**: Include tests for all new features and bug fixes

The Web application is the primary user interface that showcases all the platform's capabilities. It should provide an excellent user experience while maintaining security, performance, and scalability.
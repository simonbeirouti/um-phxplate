# Admin

The Admin application provides a comprehensive administrative interface for super administrators to manage the entire PhxplateUmbrella platform, including user management, subscription oversight, AI chat testing, and system analytics.

## Purpose

The Admin app serves as the command center for platform administrators, offering:
- **Platform Management**: Complete oversight of users, companies, and subscriptions
- **Support Tools**: Advanced customer support and troubleshooting capabilities
- **AI Testing Interface**: Direct access to AI chat features for testing and demonstration
- **Analytics Dashboard**: Platform metrics, usage statistics, and performance monitoring
- **System Administration**: User role management and platform configuration

## Key Features

### User Management
- **User Directory**: Complete list of all platform users with search and filtering
- **Role Management**: Assign and modify user roles (Basic, Admin, Super Admin)
- **User Impersonation**: Ability to log in as any user for support purposes
- **Account Actions**: Suspend, activate, or delete user accounts
- **Profile Management**: Edit user profiles and account details
- **Activity Tracking**: View user activity logs and engagement metrics

### Company Administration
- **Company Directory**: Manage all companies across the platform
- **Company Details**: Edit company information, logos, and descriptions
- **Employee Management**: View and manage company-employee relationships
- **Company Actions**: Suspend, activate, or delete company accounts
- **Invitation Oversight**: Monitor and manage employee invitations
- **Company Analytics**: Track company growth and engagement metrics

### Subscription Management
- **Billing Overview**: Complete view of all user subscriptions and billing
- **Plan Management**: Modify user subscription plans and billing cycles
- **Payment History**: Access to all payment records and transaction history
- **Subscription Actions**: Upgrade, downgrade, or cancel user subscriptions
- **Revenue Analytics**: Track platform revenue and subscription metrics
- **Stripe Integration**: Direct integration with Stripe for payment management

### Live Chat Administration
- **Chat Dashboard**: Monitor all active and historical chat sessions
- **Real-time Support**: Respond to customer support requests in real-time
- **Session Management**: Close sessions and send email transcripts
- **Support Status**: Toggle online/offline status for support availability
- **Chat Analytics**: Track support metrics and response times
- **Offline Message Management**: Handle messages received when support is offline

### AI Chat Interface
- **AI Testing Environment**: Direct access to AI chat for testing and demonstration
- **Model Selection**: Test different Claude models (Haiku, Sonnet, Opus variants)
- **Conversation Management**: Create, manage, and review AI conversations
- **Streaming Responses**: Real-time AI response testing
- **Performance Monitoring**: Track AI response times and success rates
- **Usage Analytics**: Monitor AI feature usage across the platform

### Feature Request Management
- **Request Dashboard**: View and manage all user feature requests and feedback
- **Priority Management**: Set and modify request priorities (1-10 scale)
- **Status Tracking**: Update request status and progress
- **User Communication**: Respond to users about their requests
- **Request Analytics**: Track common requests and user feedback trends
- **Implementation Planning**: Use requests to guide platform development

### Platform Analytics
- **User Metrics**: Registration trends, engagement rates, and user retention
- **Revenue Dashboard**: Subscription revenue, conversion rates, and growth metrics
- **Feature Usage**: Track which features are most/least used
- **Performance Monitoring**: Application performance and error tracking
- **Support Metrics**: Chat volume, response times, and resolution rates
- **AI Usage Statistics**: AI conversation volume and model usage patterns

## Architecture

### Phoenix LiveView Dashboard
The admin interface is built with Phoenix LiveView for real-time updates:
- **Real-time Data**: Live updates without page refreshes
- **Interactive Tables**: Sortable, filterable data tables
- **Live Charts**: Real-time analytics and metrics visualization
- **Form Handling**: Dynamic forms with live validation
- **WebSocket Updates**: Real-time notifications and status updates

### Component Structure
```
lib/admin/
├── controllers/          # HTTP request handling
├── live/                # LiveView modules
│   ├── dashboard/       # Main admin dashboard
│   ├── users/          # User management
│   ├── companies/      # Company administration
│   ├── subscriptions/  # Billing management
│   ├── chat/           # Live chat administration
│   ├── ai/            # AI chat interface
│   └── analytics/      # Platform analytics
├── components/         # Admin-specific UI components
└── templates/         # HTML templates
```

### Security & Authorization
- **Super Admin Only**: All admin features restricted to super admin role
- **Session Security**: Enhanced session management for admin users
- **Audit Logging**: Complete audit trail of all admin actions
- **IP Restrictions**: Optional IP-based access restrictions
- **Two-Factor Authentication**: Enhanced security for admin accounts

## Admin Workflows

### User Support Workflow
1. **Issue Identification**: Monitor chat sessions and user reports
2. **User Investigation**: Review user profile, activity, and subscription status
3. **Issue Resolution**: Use impersonation or direct account management
4. **Follow-up**: Track resolution and user satisfaction

### Subscription Management Workflow
1. **Billing Issue**: User reports billing problem or requests plan change
2. **Account Review**: Check subscription status and payment history
3. **Resolution**: Modify subscription, process refund, or resolve billing issue
4. **Communication**: Update user on resolution and next steps

### AI Feature Testing Workflow
1. **Model Testing**: Test different AI models for performance and accuracy
2. **Feature Validation**: Verify AI features work correctly before user rollout
3. **Performance Monitoring**: Track AI response times and error rates
4. **User Training**: Use AI interface to understand user experience

## Technical Features

### Real-time Updates
- **Live Dashboard**: Real-time metrics and status updates
- **WebSocket Integration**: Instant notifications and data refresh
- **Event Broadcasting**: Platform-wide event monitoring
- **Status Monitoring**: Real-time system health and performance

### Data Export & Reporting
- **CSV Export**: Export user, company, and subscription data
- **Custom Reports**: Generate reports for specific date ranges or criteria
- **Analytics Export**: Export analytics data for external analysis
- **Audit Trail Export**: Complete audit logs for compliance

### Integration Capabilities
- **Stripe Dashboard**: Direct links to Stripe for payment management
- **Email Integration**: Send emails directly from admin interface
- **S3 Management**: File and asset management capabilities
- **API Access**: Admin API endpoints for external integrations

## Development Setup

1. **Install Dependencies**:
   ```bash
   cd apps/admin
   mix deps.get
   ```

2. **Set Up Database** (from umbrella root):
   ```bash
   mix ecto.setup
   ```

3. **Configure Environment Variables**:
   ```bash
   # Required for full admin functionality
   export STRIPE_SECRET_KEY="sk_test_..."
   export ANTHROPIC_API_KEY="sk-ant-..."
   export RESEND_API_KEY="re_..."
   ```

4. **Create Super Admin Account**:
   ```bash
   # Run from umbrella root
   mix run -e "Phxplate.Accounts.create_super_admin(\"admin@example.com\", \"password123\")"
   ```

5. **Start Development Server**:
   ```bash
   mix phx.server
   ```

Visit [`localhost:4001`](http://localhost:4001) to access the admin interface.

## Testing

Run the admin-specific test suite:
```bash
mix test
```

Run integration tests:
```bash
mix test --only integration
```

## Security Considerations

### Access Control
- **Role Verification**: Multiple layers of super admin role verification
- **Session Management**: Enhanced session security with shorter timeouts
- **Action Logging**: Complete audit trail of all admin actions
- **IP Restrictions**: Optional IP-based access control

### Data Protection
- **Sensitive Data Handling**: Secure handling of user personal information
- **PCI Compliance**: Proper handling of payment-related data
- **Data Encryption**: Encryption of sensitive data at rest and in transit
- **Access Logging**: Complete logs of data access and modifications

## Monitoring & Alerts

### System Monitoring
- **Application Health**: Real-time application status monitoring
- **Database Performance**: Database query performance and connection health
- **Error Tracking**: Comprehensive error logging and alerting
- **Resource Usage**: CPU, memory, and disk usage monitoring

### Business Metrics
- **User Growth**: Track user registration and activation rates
- **Revenue Tracking**: Monitor subscription revenue and growth
- **Feature Adoption**: Track usage of new features and capabilities
- **Support Metrics**: Monitor support ticket volume and resolution times

## Contributing

When contributing to the Admin application:

1. **Security First**: Always consider security implications of admin features
2. **Audit Logging**: Ensure all admin actions are properly logged
3. **Performance**: Admin interfaces should be fast and responsive
4. **User Experience**: Even admin tools should have good UX design
5. **Testing**: Include comprehensive tests for all admin functionality

The Admin application is critical for platform operations and should maintain the highest standards of security, reliability, and usability. It serves as the control center that enables effective platform management and user support.

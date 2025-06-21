# UI

The UI application serves as the design system and component integration layer for the PhxplateUmbrella project, built on top of SaladUI - a comprehensive Phoenix LiveView component library that provides beautiful, accessible, and customizable UI components.

## Purpose

The UI app centralizes the design system and component customizations, offering:
- **SaladUI Integration**: Complete integration with SaladUI component library
- **Design System**: Consistent styling and theming across applications
- **Component Customization**: Tailored component variants and configurations
- **Accessibility**: WCAG-compliant components with proper accessibility features
- **Responsive Design**: Mobile-first components that work across all devices

## SaladUI Foundation

This project leverages [SaladUI](https://salad-ui.com/), a comprehensive Phoenix LiveView component library that provides:

### Available Components

#### Form Components
- **Input Fields**: Text, email, password, number, and textarea inputs with validation
- **Select Dropdowns**: Single and multi-select dropdowns with search functionality
- **Checkboxes & Radio Buttons**: Styled form controls with proper labeling
- **Buttons**: Various button styles and states (primary, secondary, outline, ghost)
- **Form Validation**: Real-time validation with error messaging and styling
- **Labels**: Consistent form labeling with proper accessibility

#### Layout Components
- **Card**: Content containers with headers, bodies, and footers
- **Sheet**: Slide-out panels and drawers
- **Dialog**: Modal dialogs and confirmations
- **Popover**: Contextual overlays and tooltips
- **Tabs**: Tab navigation for organizing content sections
- **Separator**: Visual content dividers

#### Navigation Components
- **Breadcrumb**: Hierarchical navigation breadcrumb components
- **Pagination**: Page navigation for large data sets
- **Menu**: Dropdown and context menus
- **Navigation Menu**: Main navigation components
- **Command**: Command palette and search interfaces

#### Data Display Components
- **Table**: Sortable, filterable data tables with pagination
- **Badge**: Status indicators and categorization labels
- **Avatar**: User profile images and placeholders
- **Progress**: Progress indicators for loading and completion states
- **Skeleton**: Loading placeholders for content
- **Alert**: Success, error, warning, and info messages

#### Interactive Components
- **Accordion**: Collapsible content sections
- **Collapsible**: Expandable content areas
- **Hover Card**: Contextual information on hover
- **Tooltip**: Contextual help and information overlays
- **Switch**: Toggle switches for binary options
- **Slider**: Range input controls

### Design System

#### Color Palette
SaladUI provides a comprehensive color system with:
- **Primary Colors**: Brand colors for main actions and highlights
- **Secondary Colors**: Supporting colors for secondary actions
- **Semantic Colors**: Success, warning, error, and info color schemes
- **Neutral Colors**: Grayscale palette for text and backgrounds
- **Dark Mode Support**: Complete dark theme color variations

#### Typography
- **Font Families**: Consistent font stacks optimized for readability
- **Font Sizes**: Responsive typography scale
- **Font Weights**: Proper weight hierarchy for content structure
- **Line Heights**: Optimized line spacing for readability

#### Spacing & Layout
- **Spacing Scale**: Consistent margin and padding utilities
- **Container Layouts**: Standard page and section containers
- **Grid System**: Flexible grid layouts for responsive design
- **Responsive Breakpoints**: Mobile-first responsive design tokens

## Architecture

### Component Structure
```
lib/ui/
├── components/           # Custom component extensions
│   ├── chat/            # Chat-specific components
│   ├── dashboard/       # Dashboard-specific components
│   └── custom/          # Project-specific customizations
├── themes/              # Theme configurations
│   ├── default.ex       # Default theme settings
│   └── custom.ex        # Custom theme variations
└── helpers/             # Helper functions and utilities
```

### SaladUI Integration

The UI app integrates SaladUI components with project-specific customizations:

```elixir
# Import SaladUI components
use SaladUI, :component

# Use SaladUI components directly
<.button variant="default" size="sm">
  Save Changes
</.button>

<.card class="w-full max-w-md">
  <.card_header>
    <.card_title>Login</.card_title>
    <.card_description>Enter your credentials</.card_description>
  </.card_header>
  <.card_content>
    <!-- Form content -->
  </.card_content>
</.card>
```

### Theme Customization

#### Tailwind Configuration
The project extends SaladUI's Tailwind configuration with custom design tokens:

```javascript
// tailwind.config.js
module.exports = {
  // Extend SaladUI's configuration
  theme: {
    extend: {
      colors: {
        // Custom brand colors
        brand: {
          50: '#f0f9ff',
          500: '#3b82f6',
          900: '#1e3a8a',
        }
      }
    }
  }
}
```

#### CSS Custom Properties
Dynamic theming using CSS variables:

```css
:root {
  --primary: 220 100% 50%;
  --primary-foreground: 0 0% 100%;
  --secondary: 220 14.3% 95.9%;
  --secondary-foreground: 220.9 39.3% 11%;
}

[data-theme="dark"] {
  --primary: 220 100% 60%;
  --primary-foreground: 220 100% 10%;
  --secondary: 220 14.3% 15%;
  --secondary-foreground: 220.9 39.3% 80%;
}
```

### Custom Components

For project-specific needs, custom components extend SaladUI:

```elixir
defmodule UI.Components.ChatBubble do
  use Phoenix.Component
  use SaladUI, :component
  
  attr :message, :string, required: true
  attr :sender, :string, required: true
  attr :timestamp, :string, required: true
  
  def chat_bubble(assigns) do
    ~H"""
    <.card class="mb-4 max-w-md">
      <.card_content class="p-3">
        <div class="flex justify-between items-start mb-2">
          <span class="font-semibold text-sm"><%= @sender %></span>
          <span class="text-xs text-muted-foreground"><%= @timestamp %></span>
        </div>
        <p class="text-sm"><%= @message %></p>
      </.card_content>
    </.card>
    """
  end
end
```

## Installation

Add `ui` and `salad_ui` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ui, in_umbrella: true},
    {:salad_ui, "~> 0.3.0"}
  ]
end
```

## Configuration

Configure SaladUI in your application:

```elixir
# config/config.exs
config :salad_ui,
  default_theme: "zinc",
  include_assets: true

config :ui,
  brand_colors: %{
    primary: "#3B82F6",
    secondary: "#64748B"
  }
```

## Styling Setup

Include SaladUI styles in your application:

```css
/* In your app.css */
@import "tailwindcss/base";
@import "tailwindcss/components";
@import "tailwindcss/utilities";

/* SaladUI styles are automatically included */
```

Configure Tailwind to include SaladUI components:

```javascript
// tailwind.config.js
const colors = require("tailwindcss/colors")

module.exports = {
  content: [
    "./lib/**/*.{ex,heex,js}",
    "../deps/salad_ui/lib/**/*.{ex,heex,js}",
    "../ui/lib/**/*.{ex,heex,js}"
  ],
  theme: {
    extend: {
      colors: {
        border: "hsl(var(--border))",
        input: "hsl(var(--input))",
        ring: "hsl(var(--ring))",
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        primary: {
          DEFAULT: "hsl(var(--primary))",
          foreground: "hsl(var(--primary-foreground))",
        },
        // ... other SaladUI color tokens
      }
    }
  },
  plugins: [
    require("tailwindcss-animate"),
  ]
}
```

## Usage Examples

### Using SaladUI Components

```elixir
# Form with SaladUI components
<.form for={@form} phx-submit="save">
  <div class="space-y-4">
    <div>
      <.label for="name">Full Name</.label>
      <.input field={@form[:name]} placeholder="Enter your name" />
    </div>
    
    <div>
      <.label for="email">Email</.label>
      <.input field={@form[:email]} type="email" placeholder="Enter your email" />
    </div>
    
    <.button type="submit" class="w-full">
      Create Account
    </.button>
  </div>
</.form>

# Data display with cards
<.card class="w-full">
  <.card_header>
    <.card_title>User Statistics</.card_title>
    <.card_description>Overview of user activity</.card_description>
  </.card_header>
  <.card_content>
    <div class="grid grid-cols-2 gap-4">
      <div class="text-center">
        <div class="text-2xl font-bold">1,234</div>
        <div class="text-sm text-muted-foreground">Total Users</div>
      </div>
      <div class="text-center">
        <div class="text-2xl font-bold">567</div>
        <div class="text-sm text-muted-foreground">Active Today</div>
      </div>
    </div>
  </.card_content>
</.card>

# Navigation with tabs
<.tabs default_value="overview" class="w-full">
  <.tabs_list class="grid w-full grid-cols-3">
    <.tabs_trigger value="overview">Overview</.tabs_trigger>
    <.tabs_trigger value="analytics">Analytics</.tabs_trigger>
    <.tabs_trigger value="settings">Settings</.tabs_trigger>
  </.tabs_list>
  
  <.tabs_content value="overview">
    <!-- Overview content -->
  </.tabs_content>
  
  <.tabs_content value="analytics">
    <!-- Analytics content -->
  </.tabs_content>
</.tabs>
```

## Development

### Customizing SaladUI Components

When you need to customize SaladUI components for specific use cases:

1. **Extend with CSS classes**:
   ```elixir
   <.button class="bg-gradient-to-r from-blue-500 to-purple-600">
     Gradient Button
   </.button>
   ```

2. **Create wrapper components**:
   ```elixir
   defmodule UI.Components.BrandButton do
     use Phoenix.Component
     use SaladUI, :component
     
     def brand_button(assigns) do
       ~H"""
       <.button class="bg-brand-500 hover:bg-brand-600" {@rest}>
         <%= render_slot(@inner_block) %>
       </.button>
       """
     end
   end
   ```

3. **Theme customization**:
   ```elixir
   # In your theme configuration
   defmodule UI.Themes.Custom do
     def theme_config do
       %{
         colors: %{
           primary: "220 100% 50%",
           secondary: "220 14.3% 95.9%"
         }
       }
     end
   end
   ```

### Adding Custom Components

For features not covered by SaladUI, create custom components that follow the same design principles:

```elixir
defmodule UI.Components.StatusIndicator do
  use Phoenix.Component
  use SaladUI, :component
  
  attr :status, :atom, required: true, values: [:online, :offline, :away]
  attr :class, :string, default: ""
  
  def status_indicator(assigns) do
    ~H"""
    <div class={["flex items-center gap-2", @class]}>
      <div class={[
        "w-2 h-2 rounded-full",
        status_color(@status)
      ]}>
      </div>
      <span class="text-sm capitalize"><%= @status %></span>
    </div>
    """
  end
  
  defp status_color(:online), do: "bg-green-500"
  defp status_color(:offline), do: "bg-gray-400"
  defp status_color(:away), do: "bg-yellow-500"
end
```

## Testing

Run the UI test suite:
```bash
mix test
```

Test SaladUI component integration:
```bash
mix test test/ui/components/
```

## Contributing

When contributing to the UI system:

1. **Follow SaladUI Patterns**: Use SaladUI components as the foundation
2. **Accessibility First**: Ensure all customizations maintain accessibility standards
3. **Consistent Theming**: Follow the established design tokens and color system
4. **Performance**: Consider component bundle size and rendering performance
5. **Documentation**: Update README and add usage examples for custom components

The UI application leverages SaladUI's robust component library while providing the flexibility to customize and extend components for project-specific needs. This approach ensures consistency, accessibility, and maintainability across all applications in the umbrella project.


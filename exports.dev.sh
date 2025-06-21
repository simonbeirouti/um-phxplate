#!/bin/bash

# Resend API Key
export RESEND_API_KEY="rexxx"

# Stripe Keys for Stripity Stripe
export STRIPE_SECRET_KEY="skxxx"
export STRIPE_PUBLISHABLE_KEY="pkxxx"

# AWS S3 Configuration (if using AWS instead of Tigris)
export BUCKET_NAME="xxxx"
export AWS_ACCESS_KEY_ID="xxxx"
export AWS_SECRET_ACCESS_KEY="xxxx"
export AWS_REGION="xxxx"

# Anthropic Claude API Key
export ANTHROPIC_API_KEY="sk-ant-your-key-here"

# OpenAI API Key
export OPENAI_API_KEY="sk-proj-1234567890"

echo "Environment variables exported successfully!"
echo "You can now run Phoenix with these environment variables."

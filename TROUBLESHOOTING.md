# Troubleshooting

## Table of Contents
- [AWS Credentials and Authentication](#aws-credentials-and-authentication)
  - [Understanding Your Authentication Setup](#understanding-your-authentication-setup)
  - [Standard AWS Credentials Configuration](#standard-aws-credentials-configuration)
  - [Enterprise Authentication Tools and Common Pitfalls](#enterprise-authentication-tools-and-common-pitfalls)
  - [Token Expiration and Security Errors](#token-expiration-and-security-errors)
  - [Advanced Configuration Considerations](#advanced-configuration-considerations)
- [Application Launch and Security Issues](#application-launch-and-security-issues)
  - [macOS Security Restrictions](#macos-security-restrictions)
  - [Application Crashes and Unexpected Quits](#application-crashes-and-unexpected-quits)
- [Model Access and Permissions](#model-access-and-permissions)
  - [Understanding Access Denied Errors](#understanding-access-denied-errors)
  - [IAM Permissions for Bedrock](#iam-permissions-for-bedrock)
- [Additional Troubleshooting Tips](#additional-troubleshooting-tips)
  - [Network and Connectivity Issues](#network-and-connectivity-issues)
  - [Performance and Timeout Issues](#performance-and-timeout-issues)
  - [Getting Help and Reporting Issues](#getting-help-and-reporting-issues)

---

Getting the Amazon Bedrock Client up and running can sometimes feel like solving a puzzle, especially when dealing with AWS credentials and enterprise authentication systems. This guide walks you through the most common issues and their solutions, based on real user experiences and technical insights.

## AWS Credentials and Authentication

The heart of most Bedrock Client issues lies in credential configuration. Since the client uses the AWS Swift SDK internally, it's particularly sensitive to how credentials are set up and formatted.

### Understanding Your Authentication Setup

Before diving into solutions, it's important to understand what type of AWS access you're working with. Are you using direct AWS credentials, or does your organization use an enterprise authentication system like aws-sso or similar tools? This distinction will guide which approach works best for your situation.

### Standard AWS Credentials Configuration

**Method 1: Direct Credentials in `~/.aws/credentials`**

This is the most straightforward approach when you have direct access to AWS credentials:

```ini
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
aws_session_token = YOUR_SESSION_TOKEN  # Only needed for temporary credentials
```

**Method 2: Profile-based Configuration with Credential Process**

For enterprise environments or when using authentication tools, you'll typically use the credential process approach in your `~/.aws/config` file:

```ini
[profile your-profile-name]
credential_process = /absolute/path/to/your/credential/command
region = us-east-1  # or your preferred region
```

### Enterprise Authentication Tools and Common Pitfalls

Many organizations use tools like aws-sso, SAML-based authentication, or custom enterprise authentication scripts. Based on user feedback, here are specific considerations:

**Working with Enterprise Authentication Tools:**
If you're using enterprise authentication systems, your configuration might look like this:

```ini
[profile myprofile]
credential_process = /usr/local/bin/your-auth-tool credentials --awscli user@company.com --role Admin --region eu-west-2
```

However, users have reported issues that seem related to **case sensitivity in role names**. If you're experiencing problems with a role like "Admin", try using the lowercase version "admin" if available in your organization's setup. This appears to be a quirk with how some enterprise authentication systems interact with the AWS Swift SDK.

**Common Enterprise Authentication Patterns:**
- Tools that integrate with corporate identity providers (Active Directory, SAML, etc.)
- Custom scripts that handle multi-factor authentication
- Corporate AWS CLI wrappers that manage temporary credentials
- Single sign-on solutions that generate time-limited tokens

**Critical Points for Enterprise Authentication:**
- Always use absolute paths for your credential process commands (not relative paths like `./auth-tool` or `auth-tool`)
- Ensure the credential process script or binary has proper execution permissions (`chmod +x /path/to/your/script`)
- Test your credential process independently by running it in terminal to verify it outputs valid JSON credentials
- Some enterprise tools are sensitive to role name casing - try both uppercase and lowercase versions if one doesn't work
- The Bedrock Client specifically looks for profiles, not just default credentials when using credential processes

### Token Expiration and Security Errors

When you encounter errors like "Token has expired", "Amazon_Bedrock.BedrockError error 1", or "The security token included in the request is invalid", here's how to systematically troubleshoot:

**Quick Fix Approach:**
```bash
# Manually update credentials (useful for testing)
aws configure set default.aws_access_key_id <YOUR_ACCESS_KEY>
aws configure set default.aws_secret_access_key <YOUR_SECRET_KEY>
aws configure set default.aws_session_token <YOUR_SESSION_TOKEN>  # If using temporary credentials
```

**Profile-based Fix:**
If you're using profiles, ensure you're selecting the correct profile in the Bedrock Client settings and that the profile is properly configured in your `~/.aws/config` file.

**Debugging Your Credential Process:**
You can test your credential process independently by running it directly in your terminal:

```bash
/absolute/path/to/your/credential/script
```

This should output JSON in the format:
```json
{
    "Version": 1,
    "AccessKeyId": "...",
    "SecretAccessKey": "...",
    "SessionToken": "...",
    "Expiration": "..."
}
```

### Advanced Configuration Considerations

**Environment Variables Limitation:**
Unlike many AWS tools, the Bedrock Client does not work with environment variables like `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY`. You must use credential files or credential processes.

**Region Configuration:**
Make sure your region is consistently set across your AWS configuration. Mismatched regions between your credentials and the Bedrock service can cause authentication issues.

**File Permissions and Security:**
Your `~/.aws/credentials` and `~/.aws/config` files should have restrictive permissions:
```bash
chmod 600 ~/.aws/credentials
chmod 600 ~/.aws/config
```

## Application Launch and Security Issues

### macOS Security Restrictions

If you encounter "'Amazon Bedrock Client for Mac.app' can't be opened because Apple cannot check it for malicious software":

**Method 1 (Recommended):**
1. Locate "Amazon Bedrock Client for Mac.app" in Finder
2. Right-click (or Control-click) and select "Open"
3. Click "Open" in the security dialog that appears

**Method 2 (System-wide change):**
1. Open System Preferences → Security & Privacy
2. Under "General" tab, select "Allow apps downloaded from: App Store and identified developers"
3. If you see a message about the blocked app, click "Open Anyway"

### Application Crashes and Unexpected Quits

When the Bedrock Client crashes with "Amazon Bedrock application unexpectedly quit":

**Immediate Steps:**
1. Click "Reopen" to restart the application
2. Check your credential configuration for syntax errors or invalid paths
3. Verify file permissions on your AWS configuration files

**Deeper Investigation:**
- Look at your system console logs for more detailed error messages
- Ensure your credential process (if used) is not hanging or taking too long to respond
- Try switching to direct credentials temporarily to isolate whether the issue is credential-related

## Model Access and Permissions

### Understanding Access Denied Errors

"AccessDeniedException" or "You don't have access to the model with the specified model ID" typically means your AWS account doesn't have the necessary permissions enabled for Bedrock models.

**Enabling Model Access:**
1. Navigate to the [Amazon Bedrock console](https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/)
2. Ensure you're in the correct AWS region (model availability varies by region)
3. Click "Manage Model Access" in the left sidebar
4. Select the "Model access" tab
5. Click "Edit" and enable access for the models you need:
   - Anthropic Claude models (Claude 3, Claude 3.5, etc.)
   - Amazon Titan models
   - Other foundation models as needed
6. Submit your request and wait for approval (usually instant for most models)

**Regional Considerations:**
Different AWS regions have different model availability. US East (N. Virginia) typically has the broadest selection, but check the Bedrock documentation for your specific region's offerings.

### IAM Permissions for Bedrock

Your AWS user or role needs specific IAM permissions for Bedrock. At minimum, you need:
- `bedrock:InvokeModel` for the specific models you want to use
- `bedrock:ListFoundationModels` to see available models
- Potentially `bedrock:GetModelInvocationLoggingConfiguration` for certain operations

## Additional Troubleshooting Tips

### Network and Connectivity Issues

If you're experiencing intermittent connection issues:
- Check if your organization uses proxy servers or firewall restrictions
- Verify that HTTPS traffic to AWS endpoints is allowed
- Test connectivity to Bedrock endpoints using curl or similar tools

### Performance and Timeout Issues

For slow responses or timeouts:
- Consider your AWS region proximity for better latency
- Check if you're hitting rate limits
- Monitor your network connection stability

### Getting Help and Reporting Issues

When troubleshooting doesn't resolve your issue:
- Document the exact error messages you're seeing
- Note your AWS region, authentication method, and operating system
- Test with the AWS CLI to isolate whether the issue is specific to the Bedrock Client
- Check AWS service health dashboards for any ongoing issues

Remember that the Bedrock Client uses the AWS Swift SDK internally, so some behaviors and requirements might differ slightly from other AWS tools you're familiar with. When in doubt, the most reliable approach is often to start with the simplest credential configuration that works, then gradually add complexity as needed.

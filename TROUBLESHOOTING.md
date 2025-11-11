# Troubleshooting

## Table of Contents
- [AWS Credentials and Authentication](#aws-credentials-and-authentication)
  - [Standard AWS Credentials Configuration](#standard-aws-credentials-configuration)
  - [Enterprise Authentication Tools and Common Pitfalls](#enterprise-authentication-tools-and-common-pitfalls)
  - [Token Expiration and Security Errors](#token-expiration-and-security-errors)
  - [Advanced Configuration Considerations](#advanced-configuration-considerations)
- [Application Launch and Security Issues](#application-launch-and-security-issues)
  - [macOS Security Restrictions](#macos-security-restrictions)
  - [Corporate/Managed Mac Without Admin Access](#corporatemanaged-mac-without-admin-access)
  - [Application Crashes and Unexpected Quits](#application-crashes-and-unexpected-quits)
- [Model Context Protocol (MCP) Issues](#model-context-protocol-mcp-issues)
    - [MCP Server Not Working](#mcp-server-not-working)
    - [Common MCP Configuration Issues](#common-mcp-configuration-issues)
  - [Model-Specific Issues](#model-specific-issues)
    - [Parameter Validation](#parameter-validation)
    - [IAM Permissions for Bedrock](#iam-permissions-for-bedrock)
  - [Additional Troubleshooting Tips](#additional-troubleshooting-tips)
    - [Quick Access Hotkey Issues](#quick-access-hotkey-issues)
    - [Search Performance Issues](#search-performance-issues)
    - [Network and Connectivity Issues](#network-and-connectivity-issues)
    - [Performance and Timeout Issues](#performance-and-timeout-issues)
    - [Getting Help and Reporting Issues](#getting-help-and-reporting-issues)

---

## AWS Credentials and Authentication

Most issues stem from credential configuration. The client uses the AWS Swift SDK, which requires proper credential file setup.

### Standard AWS Credentials Configuration

**Direct credentials** (`~/.aws/credentials`):

```ini
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
aws_session_token = YOUR_SESSION_TOKEN  # Only for temporary credentials
```

**Profile-based with credential process** (`~/.aws/config`):

```ini
[profile your-profile-name]
credential_process = /absolute/path/to/your/credential/command
region = us-east-1
```

Important notes:
- Environment variables (`AWS_ACCESS_KEY_ID`, etc.) are not supported
- Use absolute paths for credential process commands
- Set file permissions: `chmod 600 ~/.aws/credentials ~/.aws/config`

### Enterprise Authentication Tools and Common Pitfalls

Example configuration for enterprise SSO:

```ini
[profile myprofile]
credential_process = /usr/local/bin/your-auth-tool credentials --awscli user@company.com --role Admin --region eu-west-2
```

Common issues:
- Role name case sensitivity: try lowercase if "Admin" fails
- Missing execution permissions: `chmod +x /path/to/your/script`
- Relative paths won't work: always use absolute paths

Test your credential process independently:

```bash
/absolute/path/to/your/credential/script
```

Expected output format:
```json
{
    "Version": 1,
    "AccessKeyId": "...",
    "SecretAccessKey": "...",
    "SessionToken": "...",
    "Expiration": "..."
}
```

### Token Expiration and Security Errors

Errors like "Token has expired" or "security token invalid":

Quick fix:
```bash
aws configure set default.aws_access_key_id <YOUR_ACCESS_KEY>
aws configure set default.aws_secret_access_key <YOUR_SECRET_KEY>
aws configure set default.aws_session_token <YOUR_SESSION_TOKEN>
```

For profiles:
- Verify the correct profile is selected in Settings → Developer
- Check that the profile exists in `~/.aws/config`
- Ensure region configuration matches across files

### Advanced Configuration Considerations

**Region consistency:** Mismatched regions between credentials and Bedrock service cause authentication failures.

**Credential process requirements:**
- Must output valid JSON
- Should complete within reasonable time (no hanging)
- Profile-based credentials are preferred over default when using credential processes

## Application Launch and Security Issues

### macOS Security Restrictions

"Can't be opened because Apple cannot check it for malicious software":

**Quick fix:**
1. Right-click the app in Finder → Open
2. Click "Open" in the security dialog

**Alternative:**
System Preferences → Security & Privacy → General → Click "Open Anyway"

### Corporate/Managed Mac Without Admin Access

If you're on a company-managed Mac without administrator privileges and cannot bypass Gatekeeper restrictions, you can build and sign the app locally with your own Apple ID:

**Requirements:**
- Xcode installed (free from Mac App Store)
- Your Apple ID (free, no paid developer account needed)

**Steps:**

1. Clone the repository:
```bash
git clone https://github.com/aws-samples/amazon-bedrock-client-for-mac.git
cd amazon-bedrock-client-for-mac
```

2. Open in Xcode:
```bash
open "Amazon Bedrock Client for Mac.xcodeproj"
```

3. Configure signing:
   - Select the project in the navigator (top item)
   - Go to "Signing & Capabilities" tab
   - Check "Automatically manage signing"
   - Select your Team (add your Apple ID if needed: Xcode → Settings → Accounts)

4. Build and run:
   - Press `Cmd+R` or click the Play button
   - The app will be signed with your personal certificate
   - macOS will trust it without requiring admin approval

The built app will be located in:
```bash
~/Library/Developer/Xcode/DerivedData/Amazon_Bedrock_Client_for_Mac-*/Build/Products/Debug/
```

You can copy it to your Applications folder for regular use.

**Note:** This workaround is necessary because the distributed app is not code-signed with an Apple Developer Program certificate. See [issue #123](https://github.com/aws-samples/amazon-bedrock-client-for-mac/issues/123) for more context.

### Application Crashes and Unexpected Quits

"Application unexpectedly quit":

1. Click "Reopen"
2. Check credential configuration for syntax errors
3. Verify file permissions on AWS config files

**Debugging steps:**
- Check system console logs for detailed errors
- Ensure credential process isn't hanging
- Try direct credentials to isolate the issue

**Collecting logs:**

Application logs are stored in:
```bash
~/Amazon Bedrock Client/logs/
# Or check Settings → Developer → Advanced → Default Directory
```

To collect logs for issue reporting:
```bash
# Copy all logs to Desktop
cp -r ~/Amazon\ Bedrock\ Client/logs ~/Desktop/bedrock-logs

# Or view the latest log
ls -lt ~/Amazon\ Bedrock\ Client/logs/ | head -5
```

For system crash logs:
```bash
# View recent crash logs
log show --predicate 'process == "Amazon Bedrock Client for Mac"' --last 1h > ~/Desktop/bedrock-crash.log
```

**Report the issue:**
[Create a GitHub issue](https://github.com/aws-samples/amazon-bedrock-client-for-mac/issues/new) and attach:
- Application logs from `~/Amazon Bedrock Client/logs/`
- System crash logs (if applicable)
- Steps to reproduce the issue

**Compatibility:**
- Requires macOS 14+
- macOS 26+ gets liquid glass UI effects
- Older versions may have visual glitches but remain functional

## Model Context Protocol (MCP) Issues

### MCP Server Not Working

If your MCP server isn't connecting or tools aren't available:

**Use absolute paths for commands:**

Instead of:
```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "~"]
    }
  }
}
```

Use full paths:
```json
{
  "mcpServers": {
    "filesystem": {
      "command": "/usr/local/bin/npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/yourusername"]
    }
  }
}
```

Find command paths:
```bash
which npx    # Usually /usr/local/bin/npx or /opt/homebrew/bin/npx
which uvx    # Usually /usr/local/bin/uvx or ~/.local/bin/uvx
which node   # Usually /usr/local/bin/node or /opt/homebrew/bin/node
```

### Common MCP Configuration Issues

**Server not starting:**
- Check Settings → Developer → Model Context Protocol
- Look for connection status indicator (green = connected, gray = disconnected)
- Click "Open Config File" to verify JSON syntax
- Restart the app after config changes

**Tools not appearing:**
- Ensure the server is enabled (toggle switch on)
- Check that the command exists: `which npx` or `which uvx`
- Verify the server package is accessible
- For `uvx` servers, ensure `uv` is installed: `brew install uv`

**Permission errors:**
- MCP servers may need specific directory access
- Check that paths in args are accessible
- For filesystem server, ensure the directory exists and is readable

**Configuration location:**
Settings → Developer → Model Context Protocol → "Open Config File"

Example working configurations:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "/opt/homebrew/bin/npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/yourusername/Documents"]
    },
    "fetch": {
      "command": "/usr/local/bin/uvx",
      "args": ["mcp-server-fetch"]
    }
  }
}
```

## Model-Specific Issues

### Parameter Validation

**Claude Sonnet 4.5 and Haiku 4.5:**
These models only accept `temperature` OR `top_p`, not both. The client handles this automatically by disabling the Top P slider when these models are selected.

**Prompt Caching with PDF Documents:**
The client automatically places documents and images before text content to avoid validation errors. This issue has been resolved in recent versions.

### IAM Permissions for Bedrock

Required permissions:
- `bedrock:InvokeModel` - invoke specific models
- `bedrock:ListFoundationModels` - list available models
- `bedrock:GetModelInvocationLoggingConfiguration` - for certain operations

## Additional Troubleshooting Tips

### Quick Access Hotkey Issues

Option+Space not responding:

1. System Preferences → Privacy & Security → Accessibility
2. Enable "Amazon Bedrock Client for Mac"
3. Customize hotkey in Settings → General if there's a conflict
4. Restart the app after granting permissions

Expected behavior:
- Window appears centered on current screen
- ESC or click outside to dismiss
- Input field auto-focuses
- If no input accepted, check accessibility permissions

### Search Performance Issues

First search in a session triggers indexing:

- You'll see "Indexing chats for search..." message
- Indexing only happens when you first type in search bar
- Subsequent searches are instant
- Restart the app if search remains slow

### Network and Connectivity Issues

Connection problems:
- Check for proxy servers or firewall restrictions
- Verify HTTPS traffic to AWS endpoints is allowed
- Test connectivity: `curl https://bedrock-runtime.us-east-1.amazonaws.com`
- Ensure WebSocket connections are allowed for streaming

### Performance and Timeout Issues

Slow responses:
- Use a closer AWS region for better latency
- Check if you're hitting rate limits
- Monitor network stability
- Large documents take longer (compression applied automatically)

### Getting Help and Reporting Issues

When reporting issues, include:
- Exact error messages
- AWS region and authentication method
- macOS version
- Test with AWS CLI to isolate the issue
- Check [AWS Service Health Dashboard](https://health.aws.amazon.com/health/status)

The client uses AWS Swift SDK internally, so behavior may differ from other AWS tools. Start with the simplest credential configuration and add complexity as needed.

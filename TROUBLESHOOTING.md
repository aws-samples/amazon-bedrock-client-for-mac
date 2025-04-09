# 🛠️ Troubleshooting Guide

## AWS Credentials and Token Issues

### Configuring AWS Credentials

The most common issue users face is related to AWS credentials. The Amazon Bedrock Client requires properly configured AWS credentials. Here are the main configuration options:

**Option 1: Direct Credentials in `~/.aws/credentials`**
```ini
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
aws_session_token = YOUR_SESSION_TOKEN  # If using temporary credentials
```

**Option 2: Using credential process in `~/.aws/config`**
```ini
[profile your-profile-name]
credential_process = /absolute/path/to/your/credential/script
```

⚠️ **Important Notes**:
- Make sure key names (e.g., `aws_access_key_id`) are in lowercase
- Environment variables do NOT work with the Bedrock Client app
- Always use absolute paths for credential process commands
- If your organization uses an authentication system, ensure you've completed the necessary authentication steps first

### Common Token Errors and Solutions

If you encounter errors like "Token has expired", "Amazon_Bedrock.BedrockError error 1", or "The security token included in the request is invalid":

1. **Manually update AWS credentials** (simplest approach):
   ```sh
   aws configure set default.aws_access_key_id <YOUR_ACCESS_KEY>
   aws configure set default.aws_secret_access_key <YOUR_SECRET_KEY>
   aws configure set default.aws_session_token <YOUR_SESSION_TOKEN>  # If applicable
   ```

   - Reset or remove `[default]` in `~/.aws/config`
   - 

2. **Check your credential process configuration in `~/.aws/config`**:
   - Ensure your credential_process command uses absolute paths
   - Example: `credential_process = /absolute/path/to/your/credential/script`
   - Verify the script has proper execution permissions (`chmod +x your-script`)
   - Make sure the script outputs credentials in the correct format
   - Select this profile in the app's settings

3. **Verify credential file format**:
   - Make sure your AWS config files use the correct syntax
   - Check for case sensitivity in parameter names (must be lowercase)
   - Ensure there are no extra spaces or characters

## Opening the Application

If you see "'Amazon Bedrock Client for Mac.app' can't be opened because Apple cannot check it for malicious software":

1. Open System Preferences
2. Click Security & Privacy
3. Put a checkmark to "Allow apps downloaded from anywhere" → Click OK and enter your password

Alternatively:
1. In Finder, locate "Amazon Bedrock Client for Mac.app"
2. Right-click (or Control-click) and select "Open"
3. Click "Open" in the dialog

## Amazon Bedrock Application Unexpectedly Quit

If you encounter an error message titled "Problem Report for Amazon Bedrock" with the details "Amazon Bedrock application unexpectedly quit":

1. Restart the Application: Click the "Reopen" button to attempt restarting the application.
2. Check AWS Credentials: Ensure that your `~/.aws/credentials` or `~/.aws/config` file is correctly configured following the instructions above.
3. Look for file permissions issues or incorrect paths in your AWS config files.

## Model Access Issues

If you see "AccessDeniedException" or "You don't have access to the model with the specified model ID":

1. Go to the [Amazon Bedrock console](https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/)
2. Select the correct region
3. Click "Manage Model Access"
4. Navigate to the "Model access" tab
5. Edit settings and ensure necessary models (e.g., Anthropic Claude, Amazon Titan) are selected
6. After enabling model access, return to the Bedrock Client app and try again

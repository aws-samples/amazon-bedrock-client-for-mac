# Troubleshooting

## Updates

Automatic checks use the existing **Settings → General** preference. A manual
check is available there and in **Bedrock → Check for Updates…**, even when
automatic checks are off. Bedrock does not install an update until you approve it.

Automatic replacement requires a writable application location and a Developer
ID–signed installation. A copy running from a DMG, a read-only location, or an
unsigned source build can use **Open Downloaded DMG** and install through Finder.
Verification failures do not replace the installed app. A failed replacement
restores the previous app; a refused or unfinished quit leaves it untouched.
Conversations and preferences are stored separately and are not removed by the updater.

If a 1.x installation reports **Failed to prepare update**, install the
[latest DMG](https://github.com/aws-samples/amazon-bedrock-client-for-mac/releases/latest/download/Amazon.Bedrock.Client.for.Mac.dmg)
through Finder, replacing the app in Applications. Keep the existing data and
preferences folders. Version 2.0 fixes the temporary-download handoff used by
the older updater.

## Connect to AWS

Open **Settings → AWS connection**, choose your profile and region, then select **Test connection & refresh models**. The profile must have access to the selected model and its inference profile.

The app reads local AWS profiles, including SSO and `credential_process`. For SSO, refresh your login before reconnecting:

```sh
aws sso login --profile your-profile
```

For a credential process, use an absolute executable path in `~/.aws/config`. Keep credential values out of issue reports. A Bedrock API key can be saved in the connection pane; it is stored in macOS Keychain.

If requests fail after changing credentials, test the connection again. Check the selected region and the model's access in your AWS account. A successful catalog refresh does not guarantee permission to invoke every listed model.

## Choose a model or recover a failed request

The model picker is inside the message composer. Search by name or ID, or use a favorite. **Settings → Models** chooses the default for new conversations; the model ID is read-only.

Models can require different request APIs, inference profiles, attachments, or parameters. Image editors and upscalers require source images. Video generation requires an S3 output location. Use the matching Demo library preset and its input guidance.

For a parameter validation error, open **Response settings** and reset that model's custom parameters. For a request error, expand its details to inspect the service response. Retry creates a branch so the original conversation remains available.

## A long conversation or pasted content is slow

Scroll the complete conversation directly. Offscreen content renders as you move
through the history. **⌘F** searches the whole conversation; Global Search
(**⌘K**) searches across conversations.

Large pasted text becomes an attachment. Click it to inspect or edit the complete text before sending. Images are prepared in the background; wait for preparation to finish, or cancel it with Escape. A failed attachment does not consume the draft.

Generated images open in a bounded preview. Zoom changes the preview, while Copy and Save preserve the original image. The app avoids decoding the original image on every layout pass.

If a freeze persists, record the app version, macOS version, approximate text/image sizes, and the action that triggered it. A redacted or synthetic reproduction is more useful than a screenshot alone. Development performance checks use an optimized Release build; see [the validation procedure](development.md#performance-checks).

## Skills or tools are missing

Open **Settings → Skills** to import a `SKILL.md` file or folder, create a skill, inspect its contents, and enable it. Type `/` in the composer to choose a skill. Enabled skills can also be discovered and loaded by the model.

Open **Settings → Tools & MCP** to inspect the selected tool preset and individual tools. The default enables local tools with permissive access within macOS permissions. File access, working directory, command timeout, output limits, and approval behavior can be changed there.

Some models do not support tool calling. Choose a compatible conversational model. Expand a tool call to inspect its original input, output, duration, and errors; **Open details** provides full text, Find, and exact copying.

## An MCP server does not connect

In **Settings → Tools & MCP**, inspect the server's status and configuration. A local stdio server needs an installed executable, valid arguments, and its required environment. An HTTP server needs the correct URL and any required headers or authentication.

After correcting the configuration, reconnect that server and refresh its tools. Server-level and individual tool switches both affect what the model can use. A timeout or failed tool call is reported in the conversation instead of silently keeping the run active.

MCP configuration exports can include configured headers and environment values. Review them before sharing. Diagnostic export is a separate, limited report.

## Recover drafts and history

**⌘N** creates a new chat with the current model and keeps the previous draft. **⌘D** moves the current chat to recoverable Trash. Open **Settings → Data & history → Chat history** to view Archive and Trash and restore a conversation.

Unsent text, prepared attachments, and queued messages are stored locally. Queues interrupted by quitting or a failed request remain paused until resumed. Automations run while the app is open; missed scheduled runs are skipped after sleep or restart.

Use the app's import/export and storage-location controls when moving data. Keep the source data until you have reopened and checked the imported conversations.

## Appearance, shortcuts, and search

Choose **Light**, **Dark**, or **System** in **Settings → Appearance**. The sidebar can be resized, and **⌘B** opens or closes it. Back and **⌘[** return to the previous valid destination.

The upper-right Search button and **⌘K** open the centered global search panel. Click outside it or press Escape to dismiss it. **⌘F** opens Find inside the current conversation. Sending with Return or **⌘Return** is configurable in **Settings → Keyboard**.

Configure the Quick Access shortcut in **Settings → Keyboard**. If it conflicts
with another app, choose a different shortcut.

## Installation and reports

Use the signed app from [Releases](https://github.com/aws-samples/amazon-bedrock-client-for-mac/releases), or follow the [local build instructions](../README.md#build). Development copies and unreleased source can differ from the published release.

**Settings → Advanced → Export diagnostics** produces app/macOS versions, region, local counts, and tool configuration summaries. It excludes conversation text, credentials, and local paths. Attach a reproduction and the relevant version details to a [GitHub issue](https://github.com/aws-samples/amazon-bedrock-client-for-mac/issues).

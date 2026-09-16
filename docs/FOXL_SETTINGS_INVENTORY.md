# Foxl settings inventory

2026-09-16 · 129 indexed rows from `foxl/apps/web/src/config/settings-index.generated.ts`. Labels resolved from the same checkout’s English localization. Each source key is retained for traceability.

This is a review inventory. **Existing** requires runtime verification; **Gap** links to the implementation TODO; **Excluded** follows the requested local Bedrock scope. No row here is counted as a passed functional test.


## account

- [ ] FX-S001 **Payment past due** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `account.billing_past_due_title`.
- [ ] FX-S002 **Bio** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `account.bio`.
- [ ] FX-S003 **Blocked accounts** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `account.blocked_title`.
- [ ] FX-S004 **Credits** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `account.credits`.
- [ ] FX-S005 **Danger zone** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `account.danger_zone`.
- [ ] FX-S006 **Delete account** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `account.delete_account`.
- [ ] FX-S007 **Export my data** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `account.export_data`.
- [ ] FX-S008 **Password** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `account.password`.
- [ ] FX-S009 **Sign out everywhere** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `account.sessions_revoke_all`.
- [ ] FX-S010 **Top Up Credits** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `account.topup`.
- [ ] FX-S011 **Sign in** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.sign_in`.
- [ ] FX-S012 **Usage Breakdown** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `usage.breakdown_title`.

## advanced

- [ ] FX-S013 **Migrate from OpenClaw** — Gap: Local SKILL.md folder import exists; bulk third-party configuration migration remains (FS08). Source: `settings.migrate_openclaw`.
- [ ] FX-S014 **OpenClaw Directory (optional)** — Gap: No third-party data-root setting; local skill import is the supported entry point (FS08). Source: `settings.openclaw_dir`.
- [ ] FX-S015 **System Report** — Existing: Advanced → Export diagnostics (FN08) Source: `settings.system_report`.

## appearance

- [ ] FX-S016 **Reset onboarding** — Gap: No replayable setup flow; add only a focused AWS connection checklist if needed (FN07). Source: `settings.reset_onboarding`.

## code-local

- [ ] FX-S017 **Agents act without asking** — Existing: Tools & MCP → Tool approval (default Allow enabled tools) Source: `code_local.act_without_asking`.
- [ ] FX-S018 **Clone folder** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `code_local.clone_folder`.
- [ ] FX-S019 **Permissions** — Existing: Tools & MCP → Tool approval / File access Source: `code_local.permissions`.
- [ ] FX-S020 **Start folder** — Existing: Tools & MCP → Working directory Source: `code_local.start_folder`.
- [ ] FX-S021 **This computer** — Existing: Local file/command settings; no repository page Source: `code_local.this_computer`.

## gateway

- [ ] FX-S022 **Desktop not connected to relay** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `gateway.relay_desktop_not_connected`.
- [ ] FX-S023 **No desktop connected** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `gateway.relay_no_desktop`.
- [ ] FX-S024 **Restart Desktop App** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `gateway.relay_restart_title`.

## general

- [ ] FX-S025 **Beta updates** — Gap: No prerelease-channel setting; existing stable update checker needs validation (FN07). Source: `settings.beta_channel`.
- [ ] FX-S026 **Keep running when closed** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.daemon_mode`.
- [ ] FX-S027 **Display** — Existing: Appearance Source: `settings.display`.
- [ ] FX-S028 **EULA** — Excluded: Foxl licensing/legal screens are not portable product features. Source: `settings.eula`.
- [ ] FX-S029 **Language** — Gap: No app-language preference (FN06). Source: `settings.language`.
- [ ] FX-S030 **Auto detect** — Gap: Native system language integration incomplete (FN06). Source: `settings.language_auto`.
- [ ] FX-S031 **Launch at login** — Existing: General → Launch at login (FN07) Source: `settings.launch_at_login`.
- [ ] FX-S032 **Report an issue** — Gap: Diagnostic export exists; issue-report entry missing (FN08). Source: `settings.report_issue`.
- [ ] FX-S033 **Show in menu bar** — Existing: General → Show menu bar item (FN07) Source: `settings.show_in_menu_bar`.
- [ ] FX-S034 **Status HUD in titlebar** — Excluded: User requested a clean toolbar; inspect status in the existing run footer/Activity. Source: `settings.titlebar_hud`.

## heartbeat

- [ ] FX-S035 **Feed Generator** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.heartbeat`.
- [ ] FX-S036 **Active Hours** — Gap: Map to optional automation active hours (FA02). Source: `settings.heartbeat_active_hours`.
- [ ] FX-S037 **Always on** — Gap: Map to automation schedule, while app is running (FA02–FA03). Source: `settings.heartbeat_always_on`.
- [ ] FX-S038 **Instructions** — Gap: Existing per-automation prompt; no HEARTBEAT.md dependency (FA01). Source: `settings.heartbeat_instructions`.
- [ ] FX-S039 **Check Frequency** — Gap: Existing interval cadence; native validation remains (FA01). Source: `settings.heartbeat_interval`.

## integrations

- [ ] FX-S040 **Make Foxl work your way** — Review: Map to direct local integration settings; inspect actual control before implementation. Source: `integrations.page_title`.
- [ ] FX-S041 **Requirements** — Existing: Skills → prerequisite diagnostics (FS07) Source: `integrations.requirements_title`.
- [ ] FX-S042 **Workspace** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `integrations.workspace_title`.
- [ ] FX-S043 **Shared** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `shared_skills.title`.
- [ ] FX-S044 **Skills** — Existing: Settings → Skills (FS01–FS08) Source: `skills_page.title`.
- [ ] FX-S045 **Custom tools** — Gap: Custom shell/HTTP tools missing; MCP server configuration exists (FT08). Source: `tools_page.custom_title`.
- [ ] FX-S046 **Export** — Gap: MCP configuration export exists; generic custom tool export missing (FT09/FM04). Source: `tools_page.export`.
- [ ] FX-S047 **Import** — Gap: MCP import exists; generic custom tool replacement preview missing (FT09/FM04). Source: `tools_page.import`.
- [ ] FX-S048 **System tools** — Existing: Tools & MCP → Local tools Source: `tools_page.system_title`.
- [ ] FX-S049 **Create Tool** — Gap: Create MCP server exists; arbitrary custom tool definition missing (FT08). Source: `tools.create`.
- [ ] FX-S050 **Custom** — Existing: Custom local tool profile Source: `tools.preset_custom`.
- [ ] FX-S051 **Default** — Existing: All tools default; no restrictive preset migration Source: `tools.preset_default`.
- [ ] FX-S052 **Full** — Existing: All tools Source: `tools.preset_full`.
- [ ] FX-S053 **Minimal** — Existing: Chat only / Read only Source: `tools.preset_minimal`.
- [ ] FX-S054 **Standard** — Existing: Developer / Read only Source: `tools.preset_standard`.

## model

- [ ] FX-S055 **Bring Your Own Key** — Existing: AWS connection → local profile / Keychain API key Source: `account.byok`.
- [ ] FX-S056 **Account** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.compat_account`.
- [ ] FX-S057 **Endpoint** — Existing: AWS connection → custom endpoints Source: `settings.compat_endpoint`.
- [ ] FX-S058 **Only free models** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.compat_free_only`.
- [ ] FX-S059 **Maximum reply length (tokens)** — Existing: Models → Response settings → Maximum output Source: `settings.compat_max_output`.
- [ ] FX-S060 **{provider} options** — Existing: Models → provider-aware response settings Source: `settings.compat_options`.
- [ ] FX-S061 **Prefer** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.compat_routing_sort`.
- [ ] FX-S062 **Automatic fallback** — Gap: No configurable Bedrock fallback chain (FM08). Source: `settings.model_fallback`.
- [ ] FX-S063 **AI Provider** — Existing: Default model and composer picker; AWS connection for credentials Source: `settings.provider`.
- [ ] FX-S064 **Show older model versions** — Existing: Legacy models intentionally hidden as requested Source: `settings.show_older_models`.
- [ ] FX-S065 **Task Budget (beta)** — Gap: Output/tool-turn limits exist; provider total-task budget missing (FM12). Source: `settings.task_budget`.

## notes-ai

- [ ] FX-S066 **Show older model versions** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.show_older_models`.

## notes-export

- [ ] FX-S067 **Show older model versions** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.show_older_models`.

## notes-flow

- [ ] FX-S068 **Show older model versions** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.show_older_models`.

## notes-recording

- [ ] FX-S069 **Show older model versions** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.show_older_models`.

## notifications

- [ ] FX-S070 **Agent** — Gap: Split local response notifications by outcome (FN01). Source: `notifications.agent`.
- [ ] FX-S071 **Error** — Gap: Response-error preference missing (FN01). Source: `notifications.agent_error`.
- [ ] FX-S072 **Task Completed** — Gap: Response-success preference missing (FN01). Source: `notifications.agent_task_completed`.
- [ ] FX-S073 **Channel Messages** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.channel_messages`.
- [ ] FX-S074 **Other channels** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.channel_other`.
- [ ] FX-S075 **Device connected** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.device_connected`.
- [ ] FX-S076 **Devices** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.devices`.
- [ ] FX-S077 **Discord** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.discord`.
- [ ] FX-S078 **Email** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.email`.
- [ ] FX-S079 **Tips and offers** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.email_marketing`.
- [ ] FX-S080 **Product updates** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.email_product_updates`.
- [ ] FX-S081 **Enable Notifications** — Existing: General → Desktop notifications Source: `notifications.enable`.
- [ ] FX-S082 **Feed** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.feed`.
- [ ] FX-S083 **Quiet items** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.feed_quiet`.
- [ ] FX-S084 **Urgent items** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.feed_urgent`.
- [ ] FX-S085 **Channel messages** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.mobile_channel_messages`.
- [ ] FX-S086 **Chat replies** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.mobile_chat_done`.
- [ ] FX-S087 **Issues Foxl Code files** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.mobile_code_issues`.
- [ ] FX-S088 **Code tasks** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.mobile_code_tasks`.
- [ ] FX-S089 **Huddle invites** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.mobile_huddle_invites`.
- [ ] FX-S090 **Promotions & tips** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.mobile_marketing`.
- [ ] FX-S091 **Questions from Foxl Code** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.mobile_needs_input`.
- [ ] FX-S092 **Notes transcripts** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.mobile_notes`.
- [ ] FX-S093 **Product updates** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.mobile_product_updates`.
- [ ] FX-S094 **Push notifications** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.mobile_push`.
- [ ] FX-S095 **Scheduled tasks** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.mobile_schedules`.
- [ ] FX-S096 **Only when in background** — Existing: General → Only when in background Source: `notifications.only_background`.
- [ ] FX-S097 **Schedules** — Gap: Split local automation notifications by outcome (FN01). Source: `notifications.schedules`.
- [ ] FX-S098 **Slack** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.slack`.
- [ ] FX-S099 **Sound** — Existing: General → Notification sound Source: `notifications.sound`.
- [ ] FX-S100 **Task Completed** — Gap: Automation-success preference missing (FN01). Source: `notifications.task_completed`.
- [ ] FX-S101 **Task Failed** — Gap: Automation-error preference missing (FN01). Source: `notifications.task_failed`.
- [ ] FX-S102 **Telegram** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.telegram`.
- [ ] FX-S103 **Test** — Existing: General → Test notification (FN02) Source: `notifications.test`.
- [ ] FX-S104 **This device** — Existing: Preferences stored locally Source: `notifications.this_device`.
- [ ] FX-S105 **Web** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.web`.
- [ ] FX-S106 **WhatsApp** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `notifications.whatsapp`.

## pet

- [ ] FX-S107 **Companion** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.pet_character`.
- [ ] FX-S108 **Show outside the app window** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.pet_desktop`.
- [ ] FX-S109 **Show pet** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.pet_enabled`.
- [ ] FX-S110 **Walk around on its own** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.pet_roam`.
- [ ] FX-S111 **Size** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.pet_size`.

## safety

- [ ] FX-S112 **Tool rules** — Gap: Optional fine-grained allow/ask/deny rules missing; permissive preset remains (FT10). Source: `settings.approved_tools`.
- [ ] FX-S113 **Auto-approve all tools** — Existing: Tools & MCP → Allow enabled tools (default) Source: `settings.auto_approve_all`.
- [ ] FX-S114 **Tool Auto-Approval** — Existing: Tools & MCP → Tool approval Source: `settings.tool_approval`.

## tabbar

- [ ] FX-S115 **Show labels** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.tabbar_labels`.
- [ ] FX-S116 **Tabs** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `settings.tabbar_slots`.

## trash

- [ ] FX-S117 **Deleted chats** — Existing: Data & history → Chat history (FH12) Source: `settings.trash`.
- [ ] FX-S118 **Empty trash** — Gap: Batch Empty Trash absent (FH13). Source: `settings.trash_empty_all`.

## usage

- [ ] FX-S119 **Usage by Model** — Gap: Activity records exist; per-model aggregation missing (FA05). Source: `overview.usage_by_model`.
- [ ] FX-S120 **Usage Explorer** — Gap: Date/model aggregation and cost provenance missing (FA04–FA05). Source: `overview.usage_explorer`.

## web-access

- [ ] FX-S121 **Browser control** — Gap: No browser-control tool; external MCP can provide it. Dedicated native integration remains (FM01). Source: `web_access.browser`.
- [ ] FX-S122 **Allowed domains** — Existing: Tools & MCP → Allowed web domains (default unrestricted) Source: `web_access.domains`.
- [ ] FX-S123 **Chrome extension** — Gap: No Chrome extension connector; external MCP configuration is available (FM01). Source: `web_access.extension`.
- [ ] FX-S124 **Fetch URLs** — Existing: local_fetch_url + per-tool toggle Source: `web_access.fetch`.

## workspace

- [ ] FX-S125 **Admin control** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `org.admin_control`.
- [ ] FX-S126 **Invite people** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `org.invite_title`.
- [ ] FX-S127 **Only admins can publish shared skills** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `org.policy_admin_publish`.
- [ ] FX-S128 **Members can invite people** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `org.policy_member_invite`.
- [ ] FX-S129 **Strict security posture** — Excluded: Account/relay, Notes, projects, social channels, mobile UI, pet, billing, or unrelated background feed functionality is outside this app’s scope. Source: `org.policy_strict`.

## Additional Appearance controls

Foxl’s generated index misses these dynamic `SettingsRow` labels; source: `SettingsPage.tsx` AppearanceSection.
- [ ] FX-S130 **Theme** — Existing: Light / Dark / System; retain white-surface and dark contrast validation (FN04).
- [ ] FX-S131 **Color theme** — Excluded: requested monochrome app chrome; provider logos remain identifiable.
- [ ] FX-S132 **Surface style** — Existing: native materials with opaque light surfaces; accessibility settings need verification (FN03).
- [ ] FX-S133 **UI text size** — Gap: chat text sizing exists; settings/sidebar scale follows native system controls (FN04).
- [ ] FX-S134 **Reduce motion** — Gap: use native accessibility environment across transitions (FN03).
- [ ] FX-S135 **Use pointer cursors** — Excluded: native AppKit cursor semantics are retained.
- [ ] FX-S136 **Send messages with** — Existing: Return / Command-Return preference; retain IME/newline regression (FC15).
- [ ] FX-S137 **Channel list density** — Existing: Compact sidebar; no channel list introduced.
- [ ] FX-S138 **Show setup again** — Gap: same focused connection recovery as reset-onboarding (FN07).

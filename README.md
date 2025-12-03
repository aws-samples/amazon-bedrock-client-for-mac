# Amazon Bedrock Client for Mac

![macOS](https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square) [![Latest Release](https://img.shields.io/github/v/release/aws-samples/amazon-bedrock-client-for-mac?style=flat-square)](https://github.com/aws-samples/amazon-bedrock-client-for-mac/releases/latest) [![Swift](https://img.shields.io/badge/Swift-6.2-orange?style=flat-square)](https://swift.org) [![License: MIT-0](https://img.shields.io/badge/License-MIT--0-green.svg?style=flat-square)](https://opensource.org/license/mit-0/)

A native macOS client that brings Amazon Bedrock's AI models directly to your desktop. Access Claude Sonnet 4.5, Opus 4, and other foundation models through a clean interface designed for macOS, with system-wide quick access and full AWS integration.

<img width="2034" alt="Amazon Bedrock Client for Mac" src="assets/preview.gif" />

## Get started

### Install via Homebrew (recommended)

```bash
brew tap didhd/tap
brew install amazon-bedrock-client
```

### Or download the DMG

<a href="https://github.com/aws-samples/amazon-bedrock-client-for-mac/releases/latest/download/Amazon.Bedrock.Client.for.Mac.dmg">
  <img src="https://img.shields.io/badge/Download-Latest%20Release-blue?style=for-the-badge&logo=apple" alt="Download Latest Release" height="36">
</a>

### Configure and launch

1. Configure your AWS credentials (SSO or access keys in `~/.aws/credentials`)
2. Press **Option+Space** from anywhere to start using AI

## Core capabilities

**System-wide access**  
Press Option+Space from any application to open a lightweight AI assistant window. Ask questions, analyze code, or process documents without switching contexts.

**Native AWS integration**  
Built on Amazon Bedrock's ConverseStream API with full support for AWS SSO, credential profiles, and multi-region deployments. Your credentials stay local and secure.

**Latest foundation models**  
Access Claude Sonnet 4.5, Opus 4, Haiku 4.5, and other Bedrock models including Llama, Mistral, and DeepSeek. Multi-modal support for images and documents with prompt caching.

**Model Context Protocol**  
Extend capabilities with MCP tools and agents. Track tool usage and execution directly in your conversations.

**Built for macOS**  
Native Swift 6 application optimized for macOS 14+. Liquid glass UI effects on macOS 26+, dark mode support, and keyboard-first navigation throughout.

## Features

- Real-time streaming responses with extended thinking support
- Document and image upload (PDF, Word, images) with compression
- Conversation search and history management
- Voice transcription for hands-free input
- Custom system prompts and inference parameters
- Code generation with syntax highlighting
- Configurable hotkeys and keyboard shortcuts

## Requirements

- macOS 14 or later
- AWS account with Amazon Bedrock access
- AWS credentials configured via SSO or access keys

## Usage

Navigate to your project directory and press **Option+Space** to open Quick Access, or launch the full application from your Applications folder.

**Keyboard shortcuts:**
- `Option+Space` - Quick Access window (customizable)
- `Cmd+Shift+K` - Toggle Quick Access from menu
- `Cmd+F` - Search conversations
- `Cmd+N` - New chat
- `Cmd+,` - Settings

**Model configuration:**  
Select models from the dropdown, configure system prompts, adjust temperature and reasoning parameters in Settings.

**AWS profiles:**  
Switch between credential profiles and regions in Settings > Developer tab.

## Troubleshooting

See the [Troubleshooting Guide](TROUBLESHOOTING.md) for common issues including AWS credential setup and parameter validation.

## Contributing

Contributions are welcome. Fork the repository, create a feature branch, and submit a pull request. See the [CONTRIBUTING.md](CONTRIBUTING.md) file for details.

## License

This project is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file for details.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=aws-samples/amazon-bedrock-client-for-mac&type=Date)](https://star-history.com/#aws-samples/amazon-bedrock-client-for-mac&Date)

---

<div align="center">
Developed by the AWS Community
</div>

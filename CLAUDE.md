# Development Guide for Claude

## Build & Run Commands
- Build: `xcodebuild -project "Amazon Bedrock Client for Mac.xcodeproj" -scheme "Amazon Bedrock Client for Mac" build`
- Test: `xcodebuild -project "Amazon Bedrock Client for Mac.xcodeproj" -scheme "Amazon Bedrock Client for Mac" test`
- Run single test: `xcodebuild -project "Amazon Bedrock Client for Mac.xcodeproj" -scheme "Amazon Bedrock Client for Mac" test -only-testing:Amazon_Bedrock_Client_for_MacTests/TestClassName/testMethodName`

## Project Overview

Amazon Bedrock Client for Mac is a native macOS application that provides a user-friendly interface for interacting with Amazon Bedrock AI models. The app enables users to have conversations with AI models, upload and process images, manage documents, and search through conversation history.

## Code Style & Architecture

### Architecture
- **MVVM Pattern**: The application follows the Model-View-ViewModel architecture pattern with SwiftUI
- **Dependency Injection**: Services and managers are passed as dependencies to views and view models
- **Manager Pattern**: Business logic is encapsulated in service classes with the Manager suffix
- **Observer Pattern**: Uses Combine framework for reactive state management and data binding

### File Organization
- **Models/**: Data structures and view models
- **Views/**: SwiftUI user interface components
- **Managers/**: Service classes and business logic
- **Core/**: Core application components and configurations
- **Utils/**: Helper functions, extensions, and utilities

### Naming Conventions
- **Types**: PascalCase for classes, structs, enums, and protocols (e.g., `ChatModel`, `MessageView`)
- **Variables/Functions**: camelCase (e.g., `chatId`, `sendMessage()`)
- **Manager Services**: Descriptive names with Manager suffix (e.g., `ChatManager`, `BedrockClient`)
- **Files**: Match the primary type name (e.g., `ChatView.swift` contains `ChatView`)

### Imports
- Group framework imports first, then project imports
- Organize imports alphabetically within each group

### Types
- Prefer strong typing and Swift's type system for safety
- Use enums with associated values for state representation
- Leverage Swift's optionals for nullable values
- Use Swift's Result type for operations that can fail

### Error Handling
- Custom error enums with descriptive cases
- Use Result type or async/throws functions for error propagation
- Implement proper error handling with meaningful error messages

## Project Components

### Core Components
- **Amazon_Bedrock_Client_for_MacApp**: The main application entry point
- **AppDelegate**: Handles application lifecycle events
- **MainView**: Primary container view that orchestrates navigation
- **SidebarView**: Navigation sidebar for chat selection and management
- **ChatView**: Main conversation interface
- **MessageView**: Renders individual messages with support for markdown, code highlighting, and media

### Key Managers
- **ChatManager**: Handles chat creation, storage, and retrieval
- **BedrockClient**: Interface for Amazon Bedrock API
- **MCPManager**: Handles Model Context Protocol integration and tool usage
- **SettingManager**: Manages application settings and preferences
- **AppStateManager**: Manages global application state
- **MessageManager**: Processes and stores message data
- **TranscribeStreamingManager**: Handles speech-to-text functionality

### Models
- **ChatModel**: Represents a chat conversation
- **MessageData**: Individual message structure with support for text, images, and documents
- **ChatViewModel**: View model for chat interaction

### UI Components
- **MessageBarView**: Input interface for sending messages
- **ModelSelectorDropdown**: UI for selecting AI models
- **InferenceConfigDropdown**: Configuration UI for model parameters
- **HTMLStringView**: Custom web view for rendering markdown
- **LazyMarkdownView**: Efficiently renders markdown content
- **ImageGridView**: Displays multiple images in a grid layout

## UI/UX Guidelines

### Visual Style
- Follow macOS design guidelines and native UI patterns
- Support both light and dark mode themes
- Use system fonts and colors for consistency
- Implement proper spacing and padding for readability

### Animations
- Use subtle animations for transitions and state changes
- Keep animations quick and responsive (0.2-0.3s duration)
- Use spring animations for natural movement

### Keyboard Shortcuts
- Support standard macOS keyboard shortcuts
- Implement custom shortcuts for common actions
  - `Cmd+N`: New chat
  - `Cmd+D`: Delete chat
  - `Cmd+F`: Search in chat
  - `Cmd+B`: Toggle sidebar
  - `Cmd+,`: Open settings
  - `Cmd+Plus/Minus`: Adjust font size

## Best Practices

### SwiftUI Practices
- Use SwiftUI's property wrappers appropriately:
  - `@State`: For local component state
  - `@Binding`: For two-way bindings
  - `@ObservedObject`: For external view models that need updates
  - `@StateObject`: For owning and creating observed objects
  - `@EnvironmentObject`: For deeply injected dependencies
  - `@Environment`: For environment values like color scheme

### Dependency Injection
- Implement dependency injection through constructors
- Use environment objects for global dependencies
- Prefer explicit dependencies over singletons when possible

### Performance
- Implement efficient rendering with lazy loading
- Use background threads for heavy computations
- Cache expensive operations and results
- Implement debouncing for search and other frequent operations

### Asynchronous Operations
- Use async/await for asynchronous operations
- Properly manage UI updates on the main thread
- Implement proper cancellation for async tasks

### AWS Best Practices
- Follow AWS security best practices for credential management
- Handle API rate limiting and backoff strategies
- Implement proper error handling for AWS service calls
- Follow AWS Bedrock API best practices for model interactions

## File-by-File Functionality

### Core Files

#### Amazon_Bedrock_Client_for_MacApp.swift
- Main application entry point
- Sets up environment and logging configuration
- Defines window structure and commands

#### AppDelegate.swift
- Handles application lifecycle events
- Manages window operations and application commands

#### SidebarSelection.swift
- Defines the sidebar navigation structure
- Handles chat and model selection state

#### CoreDataStack.swift
- Provides data persistence layer
- Manages Core Data operations

### View Files

#### MainView.swift
- Primary container view
- Manages navigation between sidebar and chat view
- Handles model selection and initialization

#### SidebarView.swift
- Lists available chats organized by date
- Provides search functionality for chats
- Handles chat creation and deletion

#### ChatView.swift
- Displays conversation interface
- Manages message sending and receiving
- Implements search within conversations

#### MessageView.swift
- Renders individual message content
- Supports markdown, code blocks, and media rendering
- Handles message actions like copying

#### MessageBarView.swift
- Input interface for messages
- Manages text input, image uploads, and voice input

#### SettingsView.swift
- Configuration interface for app settings
- Manages AWS credentials and region selection
- Controls model preferences and parameters

### Manager Files

#### ChatManager.swift
- Manages chat creation, storage, and retrieval
- Handles message organization and persistence
- Coordinates between views and the Bedrock client

#### BedrockClient.swift
- Interface for Amazon Bedrock API
- Manages API requests and responses
- Handles streaming responses and model parameters

#### MCPManager.swift
- Implements Model Context Protocol (MCP)
- Manages tool usage and execution
- Coordinates between chat interface and MCP features

#### SettingManager.swift
- Stores and retrieves user preferences
- Manages AWS credentials and region selection
- Handles default model selection

#### MessageManager.swift
- Processes message content
- Handles message storage and retrieval
- Manages message formatting and parsing

#### AppStateManager.swift
- Manages global application state
- Coordinates between different components
- Handles state transitions and notifications

### Utility Files

#### Markdown.swift
- Parser for markdown content
- Converts markdown to HTML for rendering
- Custom formatting for code blocks and other elements

#### SearchEngine.swift
- Implements high-performance search functionality
- Provides highlighting and result management
- Caches search results for faster operation

#### LocalHostServer.swift
- Implements local server for web content
- Supports document previews and content rendering

#### FirstResponderTextField.swift
- Custom text field implementation
- Handles keyboard focus and events

#### EnvironmentExtensions.swift
- SwiftUI environment extensions
- Provides custom environment values and modifiers
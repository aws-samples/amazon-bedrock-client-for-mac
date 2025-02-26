# Development Guide for Claude

## Build & Run Commands
- Build: `xcodebuild -project "Amazon Bedrock Client for Mac.xcodeproj" -scheme "Amazon Bedrock Client for Mac" build`
- Test: `xcodebuild -project "Amazon Bedrock Client for Mac.xcodeproj" -scheme "Amazon Bedrock Client for Mac" test`
- Run single test: `xcodebuild -project "Amazon Bedrock Client for Mac.xcodeproj" -scheme "Amazon Bedrock Client for Mac" test -only-testing:Amazon_Bedrock_Client_for_MacTests/TestClassName/testMethodName`

## Code Style & Architecture
- **Architecture**: MVVM pattern with SwiftUI
- **File Organization**: Models/, Views/, Managers/, Core/, Utils/
- **Naming**: PascalCase for types, camelCase for variables/functions, descriptive Manager suffix for service classes
- **Imports**: Group framework imports first, then project imports
- **Types**: Prefer strong typing, use Swift's type system for safety
- **Error Handling**: Custom error enums with descriptive cases, use Result type or async/throws functions

## Best Practices
- Use SwiftUI's property wrappers appropriately (@State, @ObservedObject, @EnvironmentObject)
- Implement dependency injection through constructors
- Keep UI components focused on presentation, move business logic to ViewModels
- Use async/await for asynchronous operations
- Follow AWS Best Practices for Bedrock API interactions
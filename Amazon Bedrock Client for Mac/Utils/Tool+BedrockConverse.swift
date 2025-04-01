////
////  Tool+BedrockConverse.swift
////  Amazon Bedrock Client for Mac
////
////  Created by Na, Sanghwa on 3/24/25.
////
//
//import Foundation
//import MCPClient
//import MCPInterface
//import Logging
//import AWSBedrock
//import AWSBedrockRuntime
//
//// MCP 도구를 Bedrock Converse API 형식으로 변환하는 확장
//extension Tool {
//    
//    /// MCP 도구를 Bedrock Converse API에서 사용할 수 있는 형식으로 변환합니다.
//    func toBedrockConverseTool() -> [String: Any] {
//        // JSON inputSchema를 Bedrock 형식으로 변환
//        let bedrockInputSchema = convertToBedrockSchema()
//        
//        // Bedrock 도구 사양 형식으로 반환
//        return [
//            "toolSpec": [
//                "name": name,
//                "description": description ?? "Tool provided by MCP",
//                "inputSchema": bedrockInputSchema
//            ]
//        ]
//    }
//    
//    /// MCP 도구의 JSON 스키마를 Bedrock 호환 형식으로 변환합니다.
//    private func convertToBedrockSchema() -> [String: Any] {
//        // JSON 타입에서 객체 구조 추출
//        switch inputSchema {
//        case .object(let properties):
//            // JSON 객체의 기본 구조 생성
//            var schemaDict: [String: Any] = [
//                "type": "object"
//            ]
//            
//            // 프로퍼티 추출
//            var propertiesDict: [String: Any] = [:]
//            var requiredFields: [String] = []
//            
//            // 프로퍼티 및 필수 필드 처리
//            if let typeValue = properties["type"], case .string(let typeString) = typeValue {
//                schemaDict["type"] = typeString
//            }
//            
//            // 프로퍼티 객체 처리
//            if let propertiesValue = properties["properties"], case .object(let propsObject) = propertiesValue {
//                for (key, value) in propsObject {
//                    if case .object(let propertyObject) = value {
//                        var propDict: [String: Any] = [:]
//                        
//                        // 프로퍼티 유형 추출
//                        if let typeValue = propertyObject["type"], case .string(let typeString) = typeValue {
//                            propDict["type"] = typeString
//                        }
//                        
//                        // 설명 추출
//                        if let descValue = propertyObject["description"], case .string(let descString) = descValue {
//                            propDict["description"] = descString
//                        }
//                        
//                        // 형식 추출
//                        if let formatValue = propertyObject["format"], case .string(let formatString) = formatValue {
//                            propDict["format"] = formatString
//                        }
//                        
//                        // 열거형 값 추출
//                        if let enumValue = propertyObject["enum"], case .array(let enumArray) = enumValue {
//                            var enumValues: [String] = []
//                            for item in enumArray {
//                                if case .string(let value) = item {
//                                    enumValues.append(value)
//                                }
//                            }
//                            if !enumValues.isEmpty {
//                                propDict["enum"] = enumValues
//                            }
//                        }
//                        
//                        propertiesDict[key] = propDict
//                    }
//                }
//                
//                if !propertiesDict.isEmpty {
//                    schemaDict["properties"] = propertiesDict
//                }
//            }
//            
//            // 필수 필드 추출
//            if let requiredValue = properties["required"], case .array(let requiredArray) = requiredValue {
//                for item in requiredArray {
//                    if case .string(let field) = item {
//                        requiredFields.append(field)
//                    }
//                }
//                
//                if !requiredFields.isEmpty {
//                    schemaDict["required"] = requiredFields
//                }
//            }
//            
//            return schemaDict
//            
//        default:
//            // 기본 스키마 반환
//            return ["type": "object", "properties": [:]]
//        }
//    }
//}
//
//// MCPManager 확장 - Bedrock Converse API 도구 통합 기능
//extension MCPManager {
//    
//    /// 모든 활성 MCP 도구를 Bedrock Converse API 형식으로 가져옵니다.
//    func getBedrockConverseTools() -> [String: Any] {
//        var toolsList: [[String: Any]] = []
//        
//        // 모든 활성 서버에서 도구 수집
//        for (serverName, tools) in self.availableTools {
//            for tool in tools {
//                let bedrockTool = tool.toBedrockConverseTool()
//                toolsList.append(bedrockTool)
//            }
//        }
//        
//        // Bedrock Converse API 형식의 도구 구성 반환
//        return ["tools": toolsList]
//    }
//    
//    /// MCP 도구를 실행하는 함수
//    func executeBedrockTool(toolUseId: String, name: String, input: [String: Any]) async -> [String: Any] {
//        // 서버와 도구 이름 찾기
//        for (serverName, tools) in self.availableTools {
//            if let _ = tools.first(where: { $0.name == name }) {
//                // 도구 실행
//                let result = await callTool(serverName: serverName, toolName: name, arguments: input)
//                
//                // 결과 반환
//                return [
//                    "toolUseId": toolUseId,
//                    "content": [
//                        ["text": result ?? "Tool execution failed"]
//                    ],
//                    "status": result != nil ? "success" : "error"
//                ]
//            }
//        }
//        
//        // 도구를 찾지 못한 경우 오류 반환
//        return [
//            "toolUseId": toolUseId,
//            "content": [
//                ["text": "Tool not found: \(name)"]
//            ],
//            "status": "error"
//        ]
//    }
//}
//
//// BedrockClient 확장 - MCP 도구 통합
//extension Backend {
//    
//    /// MCP 도구를 포함하여 Claude 모델을 호출합니다.
////    func invokeClaudeModelStreamWithTools(
////        withId modelId: String,
////        messages: [ClaudeMessageRequest.Message],
////        systemPrompt: String?
////    ) async throws -> AsyncThrowingStream<BedrockRuntimeClientTypes.ResponseStream, Swift.Error> {
////        // 기본 요청 바디 생성
////        let requestBody = buildClaudeMessageRequest(
////            modelId: modelId,
////            systemPrompt: systemPrompt,
////            messages: messages
////        )
////        
////        // JSON 데이터로 인코딩
////        let encoder = JSONEncoder()
////        encoder.keyEncodingStrategy = .convertToSnakeCase
////        var jsonData = try encoder.encode(requestBody)
////        
////        // MCP 도구 가져오기
////        let mcpTools = MCPManager.shared.getBedrockConverseTools()
////        
////        // 도구 정보가 있으면 요청에 포함
////        if let toolsArray = mcpTools["tools"] as? [[String: Any]], !toolsArray.isEmpty {
////            // JSON 데이터를 수정 가능한 사전으로 변환
////            var requestDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] ?? [:]
////            
////            // toolConfig 추가
////            requestDict["toolConfig"] = mcpTools
////            
////            // 수정된 사전을 다시 JSON 데이터로 변환
////            jsonData = try JSONSerialization.data(withJSONObject: requestDict)
////            
////            logger.info("Including \(toolsArray.count) MCP tools in Bedrock request")
////        }
////        
////        // Bedrock 요청 생성 및 전송
////        let request = InvokeModelWithResponseStreamInput(
////            body: jsonData,
////            contentType: "application/json",
////            modelId: modelId
////        )
////        let output = try await self.bedrockRuntimeClient.invokeModelWithResponseStream(input: request)
////        
////        // 응답 스트림 반환
////        return output.body ?? AsyncThrowingStream { _ in }
////    }
//    
//    /// 도구 사용 요청 처리
//    func handleToolUseRequest(toolUseId: String, name: String, input: [String: Any]) async -> [String: Any] {
//        // MCP 도구 실행
//        return await MCPManager.shared.executeBedrockTool(
//            toolUseId: toolUseId,
//            name: name,
//            input: input
//        )
//    }
//}

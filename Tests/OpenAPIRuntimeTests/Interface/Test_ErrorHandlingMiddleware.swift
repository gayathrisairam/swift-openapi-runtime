//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftOpenAPIGenerator open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftOpenAPIGenerator project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftOpenAPIGenerator project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import HTTPTypes

import XCTest
@_spi(Generated) @testable import OpenAPIRuntime


final class Test_ErrorHandlingMiddlewareTests: XCTestCase {
    static let mockRequest: HTTPRequest = .init(soar_path: "http://abc.com", method: .get)
    static let mockBody: HTTPBody = HTTPBody("hello")
    static let errorHandlingMiddleware = ErrorHandlingMiddleware()

    func testSuccessfulRequest() async throws {
        let response = try await Test_ErrorHandlingMiddlewareTests.errorHandlingMiddleware.intercept(Test_ErrorHandlingMiddlewareTests.mockRequest,
                                                                                                     body: Test_ErrorHandlingMiddlewareTests.mockBody,
                                                                                                     metadata: .init(), operationID: "testop",
                                                                                                     next: getNextMiddleware(failurePhase: .never))
        XCTAssertEqual(response.0.status, .ok)
    }
    
    func testError_confirmingToProtocol_convertedToResponse() async throws {
        let (response, responseBody) = try await Test_ErrorHandlingMiddlewareTests.errorHandlingMiddleware.intercept(Test_ErrorHandlingMiddlewareTests.mockRequest,
                                                                                                     body: Test_ErrorHandlingMiddlewareTests.mockBody,
                                                                                                     metadata: .init(), operationID: "testop",
                                                                                                     next: getNextMiddleware(failurePhase: .convertibleError))
        XCTAssertEqual(response.status, .badGateway)
        XCTAssertEqual(response.headerFields, [.contentType: "application/json"])
        XCTAssertEqual(responseBody, TEST_HTTP_BODY)
    }

    
    func testError_confirmingToProtocolWithoutAllValues_convertedToResponse() async throws {
        let (response, responseBody) = try await Test_ErrorHandlingMiddlewareTests.errorHandlingMiddleware.intercept(Test_ErrorHandlingMiddlewareTests.mockRequest,
                                                                                                     body: Test_ErrorHandlingMiddlewareTests.mockBody,
                                                                                                     metadata: .init(), operationID: "testop",
                                                                                                                     next: getNextMiddleware(failurePhase: .partialConvertibleError))
        XCTAssertEqual(response.status, .badRequest)
        XCTAssertEqual(response.headerFields, [:])
        XCTAssertEqual(responseBody, nil)
    }
    
    func testError_notConfirmingToProtocol_throws() async throws {

        do {
            _ = try await Test_ErrorHandlingMiddlewareTests.errorHandlingMiddleware.intercept(Test_ErrorHandlingMiddlewareTests.mockRequest,
                                                                                                                body: Test_ErrorHandlingMiddlewareTests.mockBody,
                                                                                                                metadata: .init(), operationID: "testop",
                                                                                          next: getNextMiddleware(failurePhase: .nonConvertibleError))
            XCTFail("Expected error to be thrown")
        } catch {
            let error = error as? ServerError
            XCTAssertTrue(error?.underlyingError is NonConvertibleError)
        }
    }
        
    private func getNextMiddleware(failurePhase: MockErrorMiddleware_Next.FailurePhase) -> @Sendable (HTTPTypes.HTTPRequest,
                                                                                                     OpenAPIRuntime.HTTPBody?,
                                                                                                     OpenAPIRuntime.ServerRequestMetadata) async throws ->
                                                                            (HTTPTypes.HTTPResponse, OpenAPIRuntime.HTTPBody?) {
        
        let mockNext: @Sendable (HTTPTypes.HTTPRequest,
                                 OpenAPIRuntime.HTTPBody?,
                                 OpenAPIRuntime.ServerRequestMetadata) async throws ->
        (HTTPTypes.HTTPResponse, OpenAPIRuntime.HTTPBody?) =
        { request, body, metadata in
            try await MockErrorMiddleware_Next(failurePhase: failurePhase).intercept(request,
                                                                                    body: body,
                                                                                    metadata: metadata,
                                                                                    operationID: "testop",
                                                                                    next: { _,_,_  in (HTTPResponse.init(status: .ok), nil) })
        }
        return mockNext
    }
}

struct MockErrorMiddleware_Next: ServerMiddleware {
    enum FailurePhase {
        case never
        case convertibleError
        case nonConvertibleError
        case partialConvertibleError
    }
    var failurePhase: FailurePhase = .never

    @Sendable
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        metadata: ServerRequestMetadata,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, ServerRequestMetadata) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var error: (any Error)?
        switch failurePhase {
        case .never:
            break
        case .convertibleError:
            error = ConvertibleError()
        case .nonConvertibleError:
            error = NonConvertibleError()
        case .partialConvertibleError:
            error = PartialConvertibleError()
        }
        
        if let underlyingError = error {
            throw ServerError(operationID: operationID,
                              request: request,
                              requestBody: body,
                              requestMetadata: metadata,
                              causeDescription: "",
                              underlyingError: underlyingError)
        }
        
        let (response, responseBody) = try await next(request, body, metadata)
        return (response, responseBody)
    }
}

struct ConvertibleError: Error, HTTPResponseConvertible {
    var httpStatus: HTTPTypes.HTTPResponse.Status = HTTPResponse.Status.badGateway
    var httpHeaderFields: HTTPFields = [.contentType: "application/json"]
    var httpBody: OpenAPIRuntime.HTTPBody? = TEST_HTTP_BODY
}

struct PartialConvertibleError: Error, HTTPResponseConvertible {
    var httpStatus: HTTPTypes.HTTPResponse.Status = HTTPResponse.Status.badRequest
}

struct NonConvertibleError: Error {}

let TEST_HTTP_BODY = HTTPBody(try! JSONEncoder().encode(["error"," test error"]))

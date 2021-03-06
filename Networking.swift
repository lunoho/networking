//
//  Networking.swift
//  TheHap
//
//  Created by Luke Garner on 7/21/16.
//  Copyright © 2016 Amalgamated Bitpushers. All rights reserved.
//
import Foundation
import UIKit

public enum Result<T> {
    case Success(T)
    case Failure(Error)
}

public enum HTTPMethod: String {
    case GET    = "GET"
    case POST   = "POST"
    case PUT    = "PUT"
    case DELETE = "DELETE"
}

public enum HTTPResponseError: Error {
    case badStatusCode(statusCode: Int)
}

public let ENCODING = String.Encoding.utf8

// **************************
// **        REQUEST       **
// **************************
// http://khanlou.com/2016/05/protocol-oriented-programming/
public protocol HTTPRequest {
    var baseURL: URL? { get }
    var method: HTTPMethod { get }
    var basePath: String { get }
    var parameters: Dictionary<String, String> { get }
    var headers: Dictionary<String, String> { get }
}

public extension HTTPRequest {
    var method : HTTPMethod { return .GET }
    var basePath : String { return "" }
    var parameters : Dictionary<String, String> { return Dictionary() }
    var headers : Dictionary<String, String> { return Dictionary() }
}

public protocol ConstructableHTTPRequest: HTTPRequest {
    func buildRequest() -> URLRequest?
}

public protocol JSONConstructableHTTPRequest: ConstructableHTTPRequest { }
public extension JSONConstructableHTTPRequest {
    func buildRequest() -> URLRequest? {
        guard let baseURL = baseURL else { return nil }
        guard var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else { return nil }
        urlComponents.path = urlComponents.path + basePath
        guard let URL = urlComponents.url else { return nil }
        
        var request = URLRequest(url: URL)
        
        for (headerField, value) in headers {
            request.addValue(value, forHTTPHeaderField: headerField)
        }
        
        if method == .POST {
            request.httpBody = try? JSONSerialization.data(withJSONObject: parameters, options: [])
        }
        
        request.httpMethod = method.rawValue
        return request
    }
}

// **************************
// **       PARSING        **
// **************************
public protocol Mockable {
    static var MockJSON:Data { get }
}

public protocol ResultParsing {
    associatedtype ParsedType
    func parseData(_ data: Data) -> ParsedType?
}

public protocol StringParsing: ResultParsing { }
public extension StringParsing {
    func parseData(_ data: Data) -> String? {
        return String(data: data, encoding: ENCODING)
    }
}

// Construct base types from AnyObjects:
public protocol JSONConstructable {
    static func construct(_ with: AnyObject) -> Self?
    static func construct(_ with: [AnyObject]) -> [Self]?
}
public extension JSONConstructable {
    static func construct(_ objects: [AnyObject]) -> [Self]? {
        return objects.compactMap { self.construct($0) }
    }
}

public protocol JSONDictConstructable: JSONConstructable {
    static func construct(_ with: [AnyObject]) -> [String: Self]?
}


// Convert raw JSON Data into an associated types:
public protocol JSONParsing: ResultParsing {
    associatedtype JSONType: JSONConstructable
    func parseData(_ data: Data) -> JSONType?
}
public extension JSONParsing {
    func parseData(_ data: Data) -> JSONType? {
        guard let deserializedData = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        return JSONType.construct(deserializedData as AnyObject)
    }
}

public protocol JSONArrayParsing: ResultParsing {
    associatedtype JSONType: JSONConstructable
    func parseData(_ data: Data) -> [JSONType]?
}
public extension JSONArrayParsing {
    func parseData(_ data: Data) -> [JSONType]? {
        guard let deserializedData = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        guard let deserialzedArray = deserializedData as? [AnyObject] else { return nil }
        return JSONType.construct(deserialzedArray)
    }
}

public protocol JSONDictParsing: ResultParsing {
    associatedtype JSONType: JSONDictConstructable
    func parseData(_ data: Data) -> [String: JSONType]?
}
public extension JSONDictParsing {
    func parseData(_ data: Data) -> [String: JSONType]? {
        guard let deserializedData = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        guard let deserialzedArray = deserializedData as? [AnyObject] else { return nil }
        return JSONType.construct(deserialzedArray)
    }
}

public protocol ImageParsing: ResultParsing {
    func parseData(_ data: Data) -> UIImage?
}
public extension ImageParsing {
    func parseData(_ data: Data) -> UIImage? {
        return UIImage(data: data)
    }
}

// **************************
// **      DATA SOURCE     **
// **************************
public protocol DataSource: ResultParsing {
    func get(withHandler completionHandler:@escaping (Result<ParsedType>) -> Void)
}

public protocol SendableHTTPRequest: ConstructableHTTPRequest, DataSource { }
public extension SendableHTTPRequest {
    func sendRequest(withHandler completionHandler:@escaping (Result<ParsedType>) -> Void) {
        let session = URLSession.shared
        guard let request = buildRequest() else { return }
        let task = session.dataTask(with: request, completionHandler: { taskData, taskResponse, taskError in
            if let taskError = taskError {
                completionHandler(Result.Failure(taskError))
                return
            }
            
            guard let taskData = taskData else { return }
            guard let taskResponse = taskResponse as? HTTPURLResponse else { return }
            
            if (taskResponse.statusCode == 200) {
                guard let result = self.parseData(taskData) else { return }
                completionHandler(Result.Success(result))
            } else {
                completionHandler(Result.Failure(HTTPResponseError.badStatusCode(statusCode: taskResponse.statusCode)))
            }
        })
        task.resume()
    }
    
    public func get(withHandler completionHandler: @escaping (Result<Self.ParsedType>) -> Void) {
        sendRequest(withHandler: completionHandler)
    }
}

public protocol MockSendableRequest: DataSource {}
public extension MockSendableRequest where ParsedType: Mockable {
    func sendRequest(withHandler completionHandler:@escaping (Result<ParsedType>) -> Void) {
        print ("Sending mock")
        guard let result = self.parseData(ParsedType.MockJSON) else { return }
        completionHandler(Result.Success(result))
    }
    
    public func get(withHandler completionHandler:@escaping (Result<Self.ParsedType>) -> Void) {
        sendRequest(withHandler: completionHandler)
    }
}

// **************************
// **      CONVENIENCE     **
// **************************
public protocol Requestable: JSONConstructableHTTPRequest, SendableHTTPRequest {}
public protocol MockRequestable: MockSendableRequest {}

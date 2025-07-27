//
//  DiyanetAPIClient.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import Network

// MARK: - API Errors

enum DiyanetAPIError: LocalizedError {
    case invalidURL
    case noInternetConnection
    case invalidResponse
    case invalidDateFormat
    case serverError(code: Int, message: String)
    case decodingError(Error)
    case networkError(Error)
    case timeout
    case rateLimited
    case unauthorized
    case notFound
    case tooManyRequests
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .noInternetConnection:
            return "No internet connection available"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidDateFormat:
            return "Invalid date format in response"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .timeout:
            return "Request timed out"
        case .rateLimited:
            return "Too many requests. Please try again later"
        case .unauthorized:
            return "Unauthorized access"
        case .notFound:
            return "Resource not found"
        case .tooManyRequests:
            return "Rate limit exceeded. Please try again later"
        }
    }
}

// MARK: - Network Monitor

@Observable
class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    var isConnected = false
    var connectionType: NWInterface.InterfaceType?
    
    init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}

// MARK: - Retry Configuration

struct RetryConfiguration {
    let maxRetries: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let backoffMultiplier: Double
    let retryableStatusCodes: Set<Int>
    
    static let `default` = RetryConfiguration(
        maxRetries: 3,
        baseDelay: 1.0,
        maxDelay: 10.0,
        backoffMultiplier: 2.0,
        retryableStatusCodes: [408, 429, 500, 502, 503, 504]
    )
}

// MARK: - Diyanet API Client

@Observable
class DiyanetAPIClient {
    static let shared = DiyanetAPIClient()
    
    private let baseURL: String
    private let session: URLSession
    private let networkMonitor = NetworkMonitor()
    private let retryConfig = RetryConfiguration.default
    private let networkOptimizer = NetworkOptimizer.shared
    private let performanceMonitor = PerformanceMonitor.shared
    
    // Request timeout configuration - reduced for better UX
    private let requestTimeout: TimeInterval = 15.0
    private let resourceTimeout: TimeInterval = 30.0
    
    init(baseURL: String = "http://localhost:3001") {
        self.baseURL = baseURL
        
        // Configure URLSession with timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        
        // Set headers
        config.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "PrayerPro-macOS/1.0"
        ]
        
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public API Methods
    
    /// Fetch daily prayer times for a location
    func fetchDailyPrayerTimes(locationId: String, date: Date? = nil, method: String? = nil) async throws -> DailyPrayerScheduleResponse {
        let dateString = date?.toISO8601DateString()
        let request = DailyPrayerTimesRequest(locationId: locationId, date: dateString, method: method)
        
        do {
            let url = try buildURL(path: "/api/prayer-times/daily", queryItems: request.queryItems)
            return try await performRequest(url: url, responseType: DailyPrayerScheduleResponse.self)
        } catch {
            ErrorLogger.shared.logNetworkError(error, request: "fetchDailyPrayerTimes(locationId: \(locationId))")
            throw error
        }
    }
    
    /// Fetch annual prayer times for a location
    func fetchAnnualPrayerTimes(locationId: String, year: Int? = nil) async throws -> AnnualPrayerDataResponse {
        let request = AnnualPrayerTimesRequest(locationId: locationId, year: year)
        
        do {
            let url = try buildURL(path: "/api/prayer-times/annual", queryItems: request.queryItems)
            return try await performRequest(url: url, responseType: AnnualPrayerDataResponse.self)
        } catch {
            ErrorLogger.shared.logNetworkError(error, request: "fetchAnnualPrayerTimes(locationId: \(locationId))")
            throw error
        }
    }
    
    /// Search for locations by name
    func searchLocations(query: String, limit: Int? = nil) async throws -> LocationSearchResponse {
        let request = LocationSearchRequest(query: query, limit: limit)
        
        do {
            let url = try buildURL(path: "/api/locations/search", queryItems: request.queryItems)
            return try await performRequest(url: url, responseType: LocationSearchResponse.self)
        } catch {
            ErrorLogger.shared.logNetworkError(error, request: "searchLocations(query: \(query))")
            throw error
        }
    }
    
    /// Reverse geocode coordinates to find nearest location
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> LocationDataResponse {
        let request = ReverseGeocodeRequest(latitude: latitude, longitude: longitude)
        
        do {
            let url = try buildURL(path: "/api/locations/reverse-geocode")
            return try await performRequest(url: url, method: "POST", body: request, responseType: LocationDataResponse.self)
        } catch {
            ErrorLogger.shared.logNetworkError(error, request: "reverseGeocode(lat: \(latitude), lng: \(longitude))")
            throw error
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func buildURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: baseURL + path) else {
            throw DiyanetAPIError.invalidURL
        }
        
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        
        guard let url = components.url else {
            throw DiyanetAPIError.invalidURL
        }
        
        return url
    }
    
    private func performRequest<T: Codable>(
        url: URL,
        method: String = "GET",
        body: (any Codable)? = nil,
        responseType: T.Type
    ) async throws -> T {
        // Check network connectivity
        guard networkMonitor.isConnected else {
            throw DiyanetAPIError.noInternetConnection
        }
        
        // Perform request with retry logic
        return try await performRequestWithRetry(
            url: url,
            method: method,
            body: body,
            responseType: responseType,
            attempt: 1
        )
    }
    
    private func performRequestWithRetry<T: Codable>(
        url: URL,
        method: String,
        body: (any Codable)?,
        responseType: T.Type,
        attempt: Int
    ) async throws -> T {
        do {
            return try await performSingleRequest(
                url: url,
                method: method,
                body: body,
                responseType: responseType
            )
        } catch {
            // Check if we should retry
            if attempt <= retryConfig.maxRetries && shouldRetry(error: error) {
                let delay = calculateRetryDelay(attempt: attempt)
                
                print("Request failed (attempt \(attempt)/\(retryConfig.maxRetries)), retrying in \(delay)s: \(error.localizedDescription)")
                
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
                return try await performRequestWithRetry(
                    url: url,
                    method: method,
                    body: body,
                    responseType: responseType,
                    attempt: attempt + 1
                )
            } else {
                throw error
            }
        }
    }
    
    private func performSingleRequest<T: Codable>(
        url: URL,
        method: String,
        body: (any Codable)?,
        responseType: T.Type
    ) async throws -> T {
        // Record network request for performance monitoring
        performanceMonitor.recordNetworkRequest()
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // Add request body if provided
        if let body = body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw DiyanetAPIError.decodingError(error)
            }
        }
        
        // Check if we should defer the request for optimization
        if networkOptimizer.shouldDeferRequest() {
            let delay = networkOptimizer.getOptimalRequestDelay()
            if delay > 0 {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        // Perform the request
        let (data, response) = try await session.data(for: request)
        
        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiyanetAPIError.invalidResponse
        }
        
        // Handle different status codes
        switch httpResponse.statusCode {
        case 200...299:
            // Success - decode the response
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(responseType, from: data)
            } catch {
                throw DiyanetAPIError.decodingError(error)
            }
            
        case 400...499:
            // Client error - try to decode error response
            let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            let message = apiError?.error.message ?? "Client error"
            
            switch httpResponse.statusCode {
            case 401:
                throw DiyanetAPIError.unauthorized
            case 404:
                throw DiyanetAPIError.notFound
            case 429:
                throw DiyanetAPIError.tooManyRequests
            default:
                throw DiyanetAPIError.serverError(code: httpResponse.statusCode, message: message)
            }
            
        case 500...599:
            // Server error - try to decode error response
            let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            let message = apiError?.error.message ?? "Server error"
            throw DiyanetAPIError.serverError(code: httpResponse.statusCode, message: message)
            
        default:
            throw DiyanetAPIError.serverError(code: httpResponse.statusCode, message: "Unknown error")
        }
    }
    
    private func shouldRetry(error: Error) -> Bool {
        switch error {
        case DiyanetAPIError.networkError(_),
             DiyanetAPIError.timeout,
             DiyanetAPIError.noInternetConnection:
            return true
            
        case DiyanetAPIError.serverError(let code, _):
            return retryConfig.retryableStatusCodes.contains(code)
            
        case DiyanetAPIError.tooManyRequests:
            return true
            
        default:
            return false
        }
    }
    
    private func calculateRetryDelay(attempt: Int) -> TimeInterval {
        let exponentialDelay = retryConfig.baseDelay * pow(retryConfig.backoffMultiplier, Double(attempt - 1))
        let jitteredDelay = exponentialDelay * (0.5 + Double.random(in: 0...0.5)) // Add jitter
        return min(jitteredDelay, retryConfig.maxDelay)
    }
}

// MARK: - Date Extensions

extension Date {
    func toISO8601DateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
    
    func toISO8601String() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}

// MARK: - URLError Mapping

extension URLError {
    var diyanetAPIError: DiyanetAPIError {
        switch self.code {
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost:
            return .noInternetConnection
        default:
            return .networkError(self)
        }
    }
}
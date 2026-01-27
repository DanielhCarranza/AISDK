//
//  WeatherTool.swift
//  AISDKCLI
//
//  Live weather tool using Open-Meteo (https://open-meteo.com/)
//

import Foundation
import AISDK

/// Live weather tool that returns real weather data via Open-Meteo.
struct WeatherTool: AITool {
    let name = "get_weather"
    let description = "Get the current weather for a specified city using live data (temperature, conditions, humidity, wind, and UV index when available)."

    @AIParameter(description: "The city name to get weather for (e.g., 'Tokyo', 'New York', 'London')")
    var city: String = ""

    @AIParameter(description: "Temperature unit (celsius or fahrenheit). Defaults to celsius.")
    var unit: WeatherUnit = .celsius

    private let client: WeatherClient

    init() {
        self.client = OpenMeteoWeatherClient()
    }

    init(client: WeatherClient) {
        self.client = client
    }

    func execute() async throws -> AIToolResult {
        let report = try await client.fetchWeather(for: city, unit: unit)
        return AIToolResult(content: formatWeatherResponse(report, unit: unit))
    }

    // MARK: - Response Formatting

    private func formatWeatherResponse(_ report: WeatherReport, unit: WeatherUnit) -> String {
        let temperature = formatTemperature(report.temperature, unit: unit)
        let feelsLike = report.apparentTemperature.map { formatTemperature($0, unit: unit) } ?? "N/A"
        let humidity = report.humidity.map { "\(Int($0.rounded()))%" } ?? "N/A"
        let windSpeed = report.windSpeed.map { "\(Int($0.rounded())) \(unit.windSpeedUnit)" } ?? "N/A"
        let windDirection = report.windDirection.map { cardinalDirection(from: $0) } ?? ""
        let uvIndex = report.uvIndex.map { String(format: "%.1f", $0) } ?? "N/A"
        let observationTime = report.observationTime ?? ""
        let windDetails: String
        if windSpeed == "N/A" {
            windDetails = windSpeed
        } else if windDirection.isEmpty {
            windDetails = windSpeed
        } else {
            windDetails = "\(windSpeed) \(windDirection)"
        }

        var output = "Weather for \(report.locationName):\n\n"
        if !observationTime.isEmpty {
            output += "As of \(observationTime)\n\n"
        }

        output += "🌡️  Temperature: \(temperature)\n"
        output += "🤔  Feels like: \(feelsLike)\n"
        output += "☁️  Condition: \(report.condition)\n"
        output += "💧  Humidity: \(humidity)\n"
        output += "💨  Wind: \(windDetails)\n"
        output += "☀️  UV Index: \(uvIndex)\n\n"
        output += "Source: Open-Meteo (https://open-meteo.com/)"

        return output
    }

    private func formatTemperature(_ value: Double, unit: WeatherUnit) -> String {
        let rounded = Int(value.rounded())
        return "\(rounded)\(unit.temperatureUnit)"
    }

    private func cardinalDirection(from degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5) / 45.0) % directions.count
        return directions[index]
    }
}

// MARK: - Weather Client

enum WeatherUnit: String, Codable, CaseIterable {
    case celsius
    case fahrenheit

    var temperatureUnit: String {
        switch self {
        case .celsius:
            return "°C"
        case .fahrenheit:
            return "°F"
        }
    }

    var windSpeedUnit: String {
        switch self {
        case .celsius:
            return "km/h"
        case .fahrenheit:
            return "mph"
        }
    }

    var temperatureQueryValue: String {
        rawValue
    }

    var windSpeedQueryValue: String {
        switch self {
        case .celsius:
            return "kmh"
        case .fahrenheit:
            return "mph"
        }
    }
}

struct WeatherReport {
    let locationName: String
    let observationTime: String?
    let temperature: Double
    let apparentTemperature: Double?
    let humidity: Double?
    let condition: String
    let windSpeed: Double?
    let windDirection: Double?
    let uvIndex: Double?
}

protocol WeatherClient {
    func fetchWeather(for city: String, unit: WeatherUnit) async throws -> WeatherReport
}

protocol WeatherHTTPClient {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: WeatherHTTPClient {}

struct OpenMeteoWeatherClient: WeatherClient {
    private let session: WeatherHTTPClient
    private let geocodingBaseURL: URL
    private let forecastBaseURL: URL

    init(
        session: WeatherHTTPClient = URLSession.shared,
        geocodingBaseURL: URL = URL(string: "https://geocoding-api.open-meteo.com")!,
        forecastBaseURL: URL = URL(string: "https://api.open-meteo.com")!
    ) {
        self.session = session
        self.geocodingBaseURL = geocodingBaseURL
        self.forecastBaseURL = forecastBaseURL
    }

    func fetchWeather(for city: String, unit: WeatherUnit) async throws -> WeatherReport {
        let location = try await geocode(city)
        let forecast = try await fetchForecast(for: location, unit: unit)

        guard let current = forecast.current else {
            throw WeatherServiceError.missingCurrentWeather
        }

        let locationName = buildLocationName(location)
        let condition = weatherDescription(for: current.weatherCode)
        let uvIndex = resolveUVIndex(hourly: forecast.hourly, currentTime: current.time)

        return WeatherReport(
            locationName: locationName,
            observationTime: current.time,
            temperature: current.temperature,
            apparentTemperature: current.apparentTemperature,
            humidity: current.relativeHumidity,
            condition: condition,
            windSpeed: current.windSpeed,
            windDirection: current.windDirection,
            uvIndex: uvIndex
        )
    }

    // MARK: - API Requests

    private func geocode(_ city: String) async throws -> GeocodingResult {
        guard var components = URLComponents(url: geocodingBaseURL.appendingPathComponent("v1/search"), resolvingAgainstBaseURL: false) else {
            throw WeatherServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components.url else {
            throw WeatherServiceError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        try validate(response: response)

        let decoded = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        guard let result = decoded.results?.first else {
            throw WeatherServiceError.noResults
        }

        return result
    }

    private func fetchForecast(for location: GeocodingResult, unit: WeatherUnit) async throws -> ForecastResponse {
        guard var components = URLComponents(url: forecastBaseURL.appendingPathComponent("v1/forecast"), resolvingAgainstBaseURL: false) else {
            throw WeatherServiceError.invalidURL
        }

        let currentFields = [
            "temperature_2m",
            "apparent_temperature",
            "relative_humidity_2m",
            "weather_code",
            "wind_speed_10m",
            "wind_direction_10m"
        ]

        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: currentFields.joined(separator: ",")),
            URLQueryItem(name: "hourly", value: "uv_index"),
            URLQueryItem(name: "temperature_unit", value: unit.temperatureQueryValue),
            URLQueryItem(name: "windspeed_unit", value: unit.windSpeedQueryValue),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components.url else {
            throw WeatherServiceError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        try validate(response: response)

        return try JSONDecoder().decode(ForecastResponse.self, from: data)
    }

    private func validate(response: URLResponse) throws {
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw WeatherServiceError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Helpers

    private func buildLocationName(_ location: GeocodingResult) -> String {
        var parts = [location.name]

        if let admin1 = location.admin1, !admin1.isEmpty {
            parts.append(admin1)
        }

        if let country = location.country, !country.isEmpty {
            parts.append(country)
        }

        return parts.joined(separator: ", ")
    }

    private func weatherDescription(for code: Int) -> String {
        switch code {
        case 0:
            return "Clear sky"
        case 1, 2:
            return "Mainly clear"
        case 3:
            return "Overcast"
        case 45, 48:
            return "Fog"
        case 51, 53, 55:
            return "Drizzle"
        case 56, 57:
            return "Freezing drizzle"
        case 61, 63, 65:
            return "Rain"
        case 66, 67:
            return "Freezing rain"
        case 71, 73, 75:
            return "Snow"
        case 77:
            return "Snow grains"
        case 80, 81, 82:
            return "Rain showers"
        case 85, 86:
            return "Snow showers"
        case 95:
            return "Thunderstorm"
        case 96, 99:
            return "Thunderstorm with hail"
        default:
            return "Unknown"
        }
    }

    private func resolveUVIndex(hourly: ForecastResponse.Hourly?, currentTime: String?) -> Double? {
        guard let hourly,
              let times = hourly.time,
              let values = hourly.uvIndex,
              let currentTime,
              let index = times.firstIndex(of: currentTime),
              index < values.count else {
            return nil
        }

        return values[index]
    }
}

enum WeatherServiceError: LocalizedError {
    case invalidURL
    case httpError(statusCode: Int)
    case noResults
    case missingCurrentWeather

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Unable to build weather service URL"
        case .httpError(let statusCode):
            return "Weather service returned HTTP \(statusCode)"
        case .noResults:
            return "No matching location found"
        case .missingCurrentWeather:
            return "Weather service did not return current conditions"
        }
    }
}

// MARK: - Open-Meteo Response Models

struct GeocodingResponse: Decodable {
    let results: [GeocodingResult]?
}

struct GeocodingResult: Decodable {
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?
}

struct ForecastResponse: Decodable {
    let current: CurrentWeather?
    let hourly: Hourly?

    struct CurrentWeather: Decodable {
        let time: String
        let temperature: Double
        let apparentTemperature: Double?
        let relativeHumidity: Double?
        let weatherCode: Int
        let windSpeed: Double?
        let windDirection: Double?

        private enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case relativeHumidity = "relative_humidity_2m"
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
            case windDirection = "wind_direction_10m"
        }
    }

    struct Hourly: Decodable {
        let time: [String]?
        let uvIndex: [Double]?

        private enum CodingKeys: String, CodingKey {
            case time
            case uvIndex = "uv_index"
        }
    }
}

import Foundation

public enum ServiceError: Error {
    case unknownURL, notAnHTTPResponse, ressourceDoesNotExists, serverIssue, emptyData, emptyURL, noPresignedURL
}

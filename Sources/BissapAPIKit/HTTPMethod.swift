/// Supported HTTP verbs for `APIClient.Endpoint`.
public enum HTTPMethod: String {
    /// Fetch data without requesting a mutation.
    case get = "GET"
    /// Create or submit data to a server resource.
    case post = "POST"
    /// Remove a server resource.
    case delete = "DELETE"
    /// Partially update a server resource.
    case patch = "PATCH"
    /// Upload or fully replace a server resource.
    case put = "PUT"
}

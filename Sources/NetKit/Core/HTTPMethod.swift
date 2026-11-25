/// HTTP request method. The raw value is the method string sent on the wire.
///
/// GET, PUT and DELETE are treated as idempotent and may be retried by a ``RetryPolicy``.
/// POST and PATCH are only retried when ``SecurityPolicy/idempotencyKeys`` is enabled.
public enum HTTPMethod: String, Sendable {
    /// `GET`: read a resource. Idempotent.
    case get = "GET"
    /// `POST`: create or trigger an action. Not idempotent.
    case post = "POST"
    /// `PUT`: replace a resource. Idempotent.
    case put = "PUT"
    /// `PATCH`: partially update a resource. Not idempotent.
    case patch = "PATCH"
    /// `DELETE`: remove a resource. Idempotent.
    case delete = "DELETE"

    /// POST/PATCH thirumba anuppina duplicate aagalam
    var isIdempotent: Bool {
        switch self {
        case .get, .put, .delete: return true
        case .post, .patch: return false
        }
    }
}

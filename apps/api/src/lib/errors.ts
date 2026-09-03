/**
 * One error type with a machine-readable code, so the shape a client sees is the
 * same whether the failure came from validation, from a permission check or from a
 * missing row. Anything that is *not* an `ApiError` is a bug, and the error handler
 * treats it as one: it is logged in full and reported as an opaque 500.
 */
export class ApiError extends Error {
  readonly statusCode: number;
  readonly code: string;
  readonly details?: unknown;

  constructor(statusCode: number, code: string, message: string, details?: unknown) {
    super(message);
    this.name = 'ApiError';
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
  }

  static badRequest(message: string, details?: unknown): ApiError {
    return new ApiError(400, 'bad_request', message, details);
  }

  static unauthorized(message = 'Authentication required.'): ApiError {
    return new ApiError(401, 'unauthorized', message);
  }

  /**
   * Deliberately the same response the API gives for a row that does not exist —
   * see `notFound` below. 403 is used only where the caller is already known to be
   * allowed to see that the thing exists.
   */
  static forbidden(message = 'You do not have permission to do that.'): ApiError {
    return new ApiError(403, 'forbidden', message);
  }

  static notFound(what = 'Resource'): ApiError {
    return new ApiError(404, 'not_found', `${what} not found.`);
  }

  static conflict(message: string, details?: unknown): ApiError {
    return new ApiError(409, 'conflict', message, details);
  }

  static unprocessable(message: string, details?: unknown): ApiError {
    return new ApiError(422, 'unprocessable_entity', message, details);
  }
}

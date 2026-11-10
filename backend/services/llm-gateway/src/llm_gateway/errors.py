class GatewayError(Exception):
    status_code = 500

    def __init__(self, message: str, **extra):
        super().__init__(message)
        self.message = message
        self.extra = extra


class UnknownAlias(GatewayError):
    status_code = 404


class ProviderTimeout(GatewayError):
    status_code = 504


class ProviderUnavailable(GatewayError):
    status_code = 503


class ProviderBadResponse(GatewayError):
    status_code = 502


class QueueFull(GatewayError):
    status_code = 429


class JsonValidationFailed(GatewayError):
    status_code = 422

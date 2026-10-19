"""SentinelPay KYC API — identity verification service."""

from flask import (
    Flask,
    jsonify,
)
from werkzeug.exceptions import HTTPException
from app.routes.verify import verify_bp
from app.routes.documents import documents_bp


def create_app():
    """
    Build and configure the KYC Flask application.
    """
    app = Flask(__name__)

    # FUNCTIONALITY:
    # Register identity verification and KYC document endpoints.
    app.register_blueprint(
        verify_bp,
        url_prefix="/v1/verify",
    )

    app.register_blueprint(
        documents_bp,
        url_prefix="/v1/documents",
    )

    # FUNCTIONALITY:
    # Lightweight liveness endpoint for deployment/container health checks.
    @app.route("/health")
    def health():
        return jsonify({
            "status": "ok",
            "service": "kyc-api",
        })

    # =========================================================================
    # V-APP-09: GENERIC GLOBAL ERROR HANDLING
    # =========================================================================
    #
    # SECURITY:
    # Log full diagnostics server-side, but do not expose exception messages
    # or tracebacks to clients.

    # Remediates ZAP security alert: "Information Disclosure - Error Message Disclosure"
    @app.after_request
    def set_security_headers(response):
        response.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cross-Origin-Resource-Policy"] = "same-origin"
        response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
        response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, private"
        response.headers["Pragma"] = "no-cache"
        response.headers["Expires"] = "0"
        response.headers["Server"] = "SentinelPay"
        return response

    @app.errorhandler(HTTPException)
    def handle_http_exception(exc):
        return jsonify({"error": "resource not found" if exc.code == 404 else "request error"}), exc.code

    @app.errorhandler(Exception)
    def handle_exception(exc):
        app.logger.exception("Unhandled KYC application exception")
        return jsonify({"error": "request could not be processed"}), 500

    return app


if __name__ == "__main__":
    app = create_app()

    # SECURITY:
    # Debug is disabled to prevent Werkzeug from exposing source and interactive
    # tracebacks.

    # False Positive: Flagged for running Flask on host 0.0.0.0. 
    # Inside a Docker container, binding to 0.0.0.0 is strictly 
    # required to expose the port to the Docker daemon network.

    app.run(                      # nosemgrep  # nosec B104
        host="0.0.0.0",           # nosec B104
        port=8002,
        debug=False,
    )
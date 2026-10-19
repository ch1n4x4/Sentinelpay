FROM python:3.11-alpine

RUN apk update && apk upgrade --no-cache

WORKDIR /app

COPY requirements.txt .
RUN pip install --upgrade --no-cache-dir pip setuptools wheel && \
    pip install --no-cache-dir -r requirements.txt
COPY . .
RUN rm -f *.lock *old.txt *bak.txt Pipfile* poetry*

# Create a non-root user and group, then change ownership of the working directory
RUN addgroup -S appgroup && \
    adduser -S -G appgroup -h /app -s /sbin/nologin appuser && \
    chown -R appuser:appgroup /app

# Added HEALTHCHECK for the application on port 8001
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8001/health')" || exit 1

# CK-02 & IV-05 — Enforce the non-root USER directive
USER appuser

EXPOSE 8001

CMD ["gunicorn", "--bind", "0.0.0.0:8001", "--workers", "2", "app.main:create_app()"]

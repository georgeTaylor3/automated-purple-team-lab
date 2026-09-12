# Standard, minimal Cloud Run container for a Python Flask app.
# Cloud Run just needs: something listening on the PORT it provides,
# reachable over HTTP. Nothing here is project-specific magic --
# this is close to the generic pattern for any small Python web
# service on Cloud Run.

FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# gunicorn is a production-grade WSGI server -- more robust under
# real traffic than Flask's own built-in dev server (which main.py's
# `app.run(...)` uses, intended only for local testing).
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 main:app

FROM python:3.12-slim-bookworm

WORKDIR /app

RUN pip install --no-cache-dir flask==3.0.3 Werkzeug==3.0.3 gunicorn==22.0.0

COPY app.py        /app/app.py
COPY templates/    /app/templates/

EXPOSE 8080

ENV LOG_REFRESH_INTERVAL=30
ENV ALLOWED_NETWORKS=192.168.1.0/24,10.0.0.0/8,172.16.0.0/12

# gunicorn ile production-grade başlat
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "30", "app:app"]
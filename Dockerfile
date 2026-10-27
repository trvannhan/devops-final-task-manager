# Image chạy ứng dụng Task Manager (Flask + Gunicorn)
FROM python:3.14-slim

# Gắn image với repository để GitHub Actions có quyền đọc image trên ghcr.io
LABEL org.opencontainers.image.source="https://github.com/trvannhan/devops-final-task-manager"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Cài thư viện trước để tận dụng cache: chỉ build lại lớp này khi requirements.txt đổi
COPY requirements.txt .
RUN pip install -r requirements.txt

# Chỉ copy mã nguồn ứng dụng (tests, docs... bị loại qua .dockerignore)
COPY app ./app

# Không chạy bằng root
RUN useradd --system --uid 10001 --no-create-home appuser
USER appuser

# Phiên bản (git commit) được truyền vào lúc build, hiển thị ở /health và chân trang
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status == 200 else 1)"

CMD ["gunicorn", "--workers", "2", "--bind", "0.0.0.0:8000", "--access-logfile", "-", "app.main:app"]

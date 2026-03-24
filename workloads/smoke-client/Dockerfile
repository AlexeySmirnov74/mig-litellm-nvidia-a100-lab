FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir requests
COPY smoke_test.py /app/smoke_test.py
CMD ["python", "/app/smoke_test.py"]

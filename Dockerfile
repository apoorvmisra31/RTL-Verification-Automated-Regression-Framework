FROM python:3.11-slim

# Install system dependencies: Icarus Verilog and GNU Make
RUN apt-get update && \
    apt-get install -y --no-install-recommends iverilog make && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY . .

CMD ["python3", "scripts/dashboard_server.py"]

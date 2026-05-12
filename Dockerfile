FROM python:3.10-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1
ENV POETRY_VERSION=2.4.0

RUN pip install "poetry==$POETRY_VERSION"

COPY pyproject.toml poetry.lock ./

RUN poetry config virtualenvs.create false \
    && poetry install --no-root --only main

COPY app ./app

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
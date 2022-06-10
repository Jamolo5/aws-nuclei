FROM python:3.9.10-buster

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONFAULTHANDLER=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONHASHSEED=random \
    PIP_NO_CACHE_DIR=off \
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PIP_DEFAULT_TIMEOUT=100 \
    POETRY_VERSION=1.0.10 \
    MODULE_NAME=mappings

RUN apt-get update
RUN apt-get install zip

RUN pip install "poetry==${POETRY_VERSION}" 

RUN mkdir /app /dist 

WORKDIR /app

## The following is based upon https://github.com/python-poetry/poetry/issues/1301#issuecomment-609009714

# Only copying these files here in order to take advantage of Docker cache. We only want the
# next stage (poetry install) to run if these files change, but not the rest of the app.
COPY pyproject.toml poetry.lock ./

# Currently poetry install is significantly slower than pip install, so we're creating a
# requirements.txt output and running pip install with it.
# Follow this issue: https://github.com/python-poetry/poetry/issues/338
# Setting --without-hashes because of this issue: https://github.com/pypa/pip/issues/4995
RUN poetry config virtualenvs.create true \
    && poetry export --without-hashes -f requirements.txt --output requirements.txt \
    && poetry run pip install -r requirements.txt -t . \
    && poetry debug

COPY  "." ./

# Because initially we only copy the lock and pyproject file, we can only install the dependencies
# in the RUN above, as the `packages` portion of the pyproject.toml file is not
# available at this point. Now, after the whole package has been copied in, we run `poetry install`
# again to only install packages, scripts, etc. (and thus it should be very quick).
# See this issue for more context: https://github.com/python-poetry/poetry/issues/1899
RUN poetry install --no-interaction --no-dev

RUN ls -la

RUN chmod 754 lambda_function.py

RUN zip -r /dist/dist.zip .

ENTRYPOINT ["cp", "/dist/dist.zip", "/github/workspace/dist.zip"]
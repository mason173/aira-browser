class PublicError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

function fail(status, code, message) {
  throw new PublicError(status, code, message);
}

function buildPublicError(code, message) {
  return new PublicError(400, code, message);
}

function toPublicError(error) {
  if (error instanceof PublicError) {
    return {
      status: error.status,
      body: { ok: false, code: error.code, message: error.message },
    };
  }
  console.error(error);
  return {
    status: 500,
    body: { ok: false, code: 'internal_error', message: 'Internal server error.' },
  };
}

module.exports = { PublicError, buildPublicError, fail, toPublicError };

const logAxiosError = (context, error) => {
  // Axios error objects contain the full request, even the headers.
  // And the header contains the API key being used.
  // So, to be safe, we just log the message and the url
  const details = {
    context,
    // All error types _should_ have this field
    message: error.message,
    // Axios errors will have this field
    ...(error.config?.url) && {url: error.config?.url}, // Crazy ES6 stuff: https://stackoverflow.com/a/40560953
  };

  console.error(details);
}

module.exports = { logAxiosError }